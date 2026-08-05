################################################################################
# k3d test fleet
#
# One EC2 box in the eks-hub VPC running several single-node k3d clusters, so
# the org-level agent on eks-hub can register them as ordinary Argo
# destinations and a new addons chart version can be rolled at them
# progressively before it reaches anything real.
#
# WHY EC2 IN THE VPC AND NOT k3d ON A LAPTOP: Argo CD DIALS its destinations.
# k3d on a workstation publishes its API to a Docker port map on that machine,
# which nothing in eu-west-2 can route to - the cluster Secrets would apply
# cleanly and every Application against them would sit Unknown forever. In this
# VPC the CNI gives Argo's pods real 10.0.x.x addresses, so reachability is a
# security group rule and nothing more. No tunnel, no tailnet, no laptop.
################################################################################

locals {
  # Deterministic subnet choice. `sort` matters: aws_subnets returns ids in
  # unspecified order, so without it a no-op plan could propose moving the
  # instance to another AZ.
  subnet_id = element(sort(data.aws_subnets.private.ids), 0)

  name = var.name
}

################################################################################
# Network access
################################################################################

resource "aws_security_group" "this" {
  name        = local.name
  description = "k3d test fleet - API access from eks-hub nodes only"
  vpc_id      = data.aws_vpc.this.id

  tags = merge(var.tags, { Name = local.name })

  lifecycle {
    # Fail LOUDLY rather than apply a fleet nothing can reach. An empty result
    # here would for_each over nothing, create zero ingress rules, and leave a
    # perfectly healthy instance that Argo cannot connect to - exactly the kind
    # of silent success this codebase keeps getting bitten by.
    precondition {
      condition     = length(data.aws_security_groups.eks_nodes.ids) > 0
      error_message = "No security group matching ${var.eks_cluster_name}-node-* in the VPC. Check eks_cluster_name - without a node SG the k3d API ports would be unreachable from Argo."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "api_from_eks_nodes" {
  for_each = toset(data.aws_security_groups.eks_nodes.ids)

  security_group_id = aws_security_group.this.id
  description       = "k3d API servers from EKS nodes (Argo pods egress via the node ENI)"

  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = min([for c in var.clusters : c.api_port]...)
  to_port                      = max([for c in var.clusters : c.api_port]...)

  tags = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "api_from_extra_cidrs" {
  for_each = toset(var.extra_ingress_cidrs)

  security_group_id = aws_security_group.this.id
  description       = "k3d API servers from an explicitly allowed CIDR"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = min([for c in var.clusters : c.api_port]...)
  to_port     = max([for c in var.clusters : c.api_port]...)

  tags = var.tags
}

# Egress is wide open on purpose: the box pulls from Docker Hub, the k3s
# release bucket, GitHub and dl.k8s.io during bootstrap, all via the VPC's NAT.
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Image and binary pulls via NAT"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"

  tags = var.tags
}

################################################################################
# Instance identity
#
# SSM Session Manager only - no key pair, no public IP, no inbound SSH. The VPC
# already has a NAT gateway, so the SSM agent reaches its endpoints without
# needing interface endpoints added.
################################################################################

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}-instance"
  role = aws_iam_role.this.name
  tags = var.tags
}

################################################################################
# The box
################################################################################

resource "aws_instance" "this" {
  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type
  subnet_id     = local.subnet_id

  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # Private subnet, and stated explicitly so nobody "fixes" reachability later
  # by giving this box a public address instead of a security group rule.
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    clusters = var.clusters
  })

  # Changing user_data must REBUILD the fleet, not silently leave an instance
  # running the old bootstrap. The script is the entire definition of what these
  # clusters are; an in-place update would apply to nothing.
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
    tags        = merge(var.tags, { Name = local.name })
  }

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 required. The bootstrap script fetches the private IP from IMDS to
    # build the k3s TLS SANs, and does so with a token for this reason.
    http_tokens = "required"
  }

  tags = merge(var.tags, { Name = local.name })
}
