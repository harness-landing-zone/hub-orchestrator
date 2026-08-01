module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.17"

  name                   = local.cluster_name
  kubernetes_version     = local.cluster_version
  endpoint_public_access = var.eks_cluster_endpoint_public_access

  # Disable control plane logs to save ~$60/mo
  enabled_log_types           = []
  create_cloudwatch_log_group = false

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  security_group_additional_rules = {
    cluster_internal_ingress = {
      description = "Access EKS from VPC."
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  enable_cluster_creator_admin_permissions = false
  access_entries = {
    # access entry with a policy associated for admins
    kube-admins = {
      principal_arn = tolist(data.aws_iam_roles.eks_admin_role.arns)[0]
      policy_associations = {
        admins = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }



  eks_managed_node_groups = local.enable_automode ? {} : {
    platform = {
      name            = "platform-2xl"
      use_name_prefix = false
      tags = {
        GithubRepo = null
      }
      iam_role_name = "platform-eks-node-group"
      iam_role_tags = {
        GithubRepo = "https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest"
      }
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore    = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
        AmazonSSMDirectoryServiceAccess = "arn:aws:iam::aws:policy/AmazonSSMDirectoryServiceAccess",
        CloudWatchAgentServerPolicy     = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }
      instance_types = ["m5.2xlarge"]
      ami_type       = var.managed_node_group_ami
      # In Case you want to control the version of the ami
      ami_release_version            = var.ami_release_version
      use_latest_ami_release_version = var.managed_node_group_ami != "" ? false : true
      min_size                       = 2
      max_size                       = 6
      desired_size                   = 2
      create_launch_template         = false
      use_custom_launch_template     = true
      launch_template_id             = "lt-0c746cad72ba1ea11"
      launch_template_version        = "1"
    }
  }

  #############################################
  # 100 % working Auto-Mode toggle
  #############################################
  compute_config = local.cluster_compute_config


  # EKS Addons
  # If automode is enabled the following addons are managed by Automode
  addons = local.enable_automode ? {} : {
    coredns = {
      addon_version = "v1.14.3-eksbuild.3"
    }
    kube-proxy = {
      addon_version = "v1.36.0-eksbuild.9"
    }
    aws-ebs-csi-driver = {
      addon_version = "v1.62.0-eksbuild.1"
    }
    amazon-cloudwatch-observability = {
      addon_version = "v6.2.0-eksbuild.1"
    }
    eks-pod-identity-agent = {
      addon_version = "v1.3.10-eksbuild.3"
    }
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      before_compute = true
      addon_version  = "v1.22.2-eksbuild.1"
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
  }
  node_security_group_additional_rules = {
    # Allows Control Plane Nodes to talk to Worker nodes vpc cni metrics port
    vpc_cni_metrics_traffic = {
      description                   = "Cluster API to node 61678/tcp vpc cni metrics"
      protocol                      = "tcp"
      from_port                     = 61678
      to_port                       = 61678
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }
  node_security_group_tags = {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = {
    Blueprint  = local.cluster_name
    GithubRepo = "https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest"
  }

}

locals {
  # Table with BOTH Posiblilities AUTO-Mode on or off
  _cluster_compute_configs = {
    true = { # Auto-Mode ON
      enabled    = true
      node_pools = ["general-purpose", "system"]
    }
    false = {} # Auto-Mode OFF
  }

  # Pick the one we need at runtime
  cluster_compute_config = local._cluster_compute_configs[tostring(local.enable_automode)]
}

################################################################################
# Hub cluster metadata secret (unchanged — used for spoke registration)
################################################################################
resource "aws_secretsmanager_secret" "hub_cluster_secret" {
  name                    = "hub/${local.cluster_name}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "hub_cluster_secret_version" {
  secret_id = aws_secretsmanager_secret.hub_cluster_secret.id
  secret_string = jsonencode({
    cluster_name = module.eks.cluster_name
    metadata     = local.addons_metadata
    addons       = {}
    server       = module.eks.cluster_endpoint
    config = {
      tlsClientConfig = {
        insecure = false,
        caData   = module.eks.cluster_certificate_authority_data
      },
      # awsAuthConfig = {
      #   clusterName = module.eks.cluster_name,
      #   roleARN     = aws_iam_role.spoke.arn
      # }
    }
  })
}
