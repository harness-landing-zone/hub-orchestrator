################################################################################
# External Secrets EKS Access
################################################################################
module "external_secrets_pod_identity" {
  count   = local.aws_resources.enable_external_secrets ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12.0"

  name = "external-secrets"

  external_secrets_create_permission  = false
  attach_external_secrets_policy      = true
  external_secrets_kms_key_arns       = ["arn:aws:kms:*:*:key/*"]
  external_secrets_ssm_parameter_arns = ["arn:aws:ssm:${local.region}:*:parameter/${module.eks.cluster_name}/*"]
  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:${local.region}:*:secret:hub/${module.eks.cluster_name}*",
    "arn:aws:secretsmanager:${local.region}:*:secret:${module.eks.cluster_name}/*",
    "arn:aws:secretsmanager:${local.region}:*:secret:github*"
  ]

  additional_policy_arns = {
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.external_secrets.namespace
      service_account = local.external_secrets.service_account
    }
  }

  tags = local.tags
}

################################################################################
# Adding the secret arn in parameter store so we can share it with the hub account
################################################################################
resource "aws_ssm_parameter" "external_secret_role" {
  count = local.aws_resources.enable_external_secrets ? 1 : 0
  name  = "/${local.cluster_name}/external-secret-role"
  type  = "String"
  value = module.external_secrets_pod_identity[0].iam_role_arn
}
################################################################################
# CloudWatch Observability EKS Access
################################################################################
module "aws_cloudwatch_observability_pod_identity" {
  count   = local.aws_resources.enable_aws_cloudwatch_observability ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12.0"

  name = "aws-cloudwatch-observability"

  attach_aws_cloudwatch_observability_policy = true

  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = module.eks.cluster_name
      namespace       = "amazon-cloudwatch"
      service_account = "cloudwatch-agent"
    }
  }

  tags = local.tags
}

################################################################################
# EBS CSI EKS Access
################################################################################
# module "aws_ebs_csi_pod_identity" {
#   source  = "terraform-aws-modules/eks-pod-identity/aws"
#   version = "~> 1.12.0"

#   name = "aws-ebs-csi"

#   attach_aws_ebs_csi_policy = true
#   aws_ebs_csi_kms_arns      = ["arn:aws:kms:*:*:key/*"]

#   # Pod Identity Associations
#   associations = {
#     addon = {
#       cluster_name    = module.eks.cluster_name
#       namespace       = "kube-system"
#       service_account = "ebs-csi-controller-sa"
#     }
#   }

#   tags = local.tags
# }

################################################################################
# AWS ALB Ingress Controller EKS Access
################################################################################
module "aws_lb_controller_pod_identity" {
  count   = local.aws_resources.enable_aws_load_balancer_controller || local.enable_automode ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12.0"

  name = "aws-lbc"

  attach_aws_lb_controller_policy = true


  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = module.eks.cluster_name
      namespace       = local.aws_load_balancer_controller.namespace
      service_account = local.aws_load_balancer_controller.service_account
    }
  }

  tags = local.tags
}

################################################################################
# Karpenter EKS Access
################################################################################

module "karpenter" {
  count   = local.aws_resources.enable_karpenter ? 1 : 0
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.17"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true

  iam_role_name                 = "${module.eks.cluster_name}-karpenter"
  node_iam_role_use_name_prefix = false
  namespace                     = local.karpenter.namespace
  service_account               = local.karpenter.service_account

  # Used to attach additional IAM policies to the Karpenter node IAM role
  # Adding IAM policy needed for fluentbit
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    CloudWatchAgentServerPolicy  = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  tags = local.tags
}

################################################################################
# VPC CNI Helper
################################################################################
resource "aws_iam_policy" "cni_metrics_helper_pod_identity_policy" {
  count       = local.aws_resources.enable_cni_metrics_helper ? 1 : 0
  name_prefix = "cni_metrics_helper_pod_identity"
  path        = "/"
  description = "Policy to allow cni metrics helper put metcics to cloudwatch"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

module "cni_metrics_helper_pod_identity" {
  count   = local.aws_resources.enable_cni_metrics_helper ? 1 : 0
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12.0"
  name    = "cni-metrics-helper"

  additional_policy_arns = {
    "cni-metrics-help" : aws_iam_policy.cni_metrics_helper_pod_identity_policy[0].arn
  }

  # Pod Identity Associations
  associations = {
    addon = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "cni-metrics-helper"
    }
  }
  tags = local.tags
}

################################################################################
# Creating parameter for argocd hub role for the spoke clusters to read
################################################################################
resource "aws_ssm_parameter" "argocd_hub_role" {
  name  = "/${local.cluster_name}/agent-hub-role"
  type  = "String"
  value = module.argocd_hub_pod_identity.iam_role_arn
}

module "argocd_hub_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12.0"

  name = "harness-agent"

  attach_custom_policy = true
  policy_statements = [
    {
      sid       = "harness"
      actions   = ["sts:AssumeRole", "sts:TagSession"]
      resources = ["*"]
    }
  ]

  # Pod Identity Associations
  association_defaults = {
    namespace = "harness-agent"
  }
  associations = {
    controller = {
      cluster_name    = module.eks.cluster_name
      service_account = "argocd-application-controller"
    }
    server = {
      cluster_name    = module.eks.cluster_name
      service_account = "gitops-agent"
    }
  }

  tags = local.tags
}