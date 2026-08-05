################################################################################
# Lookups against what eks-hub already built
################################################################################

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

# PRIVATE subnets only. The instance has no public IP and is reached over SSM,
# so a public subnet would buy nothing and expose the k3d API ports to the
# internet-facing side of the VPC.
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}-private-*"]
  }
}

# The security group EKS attaches to NODES, not the cluster SG.
#
# This distinction is load-bearing and was verified rather than assumed: the
# running nodes carry exactly one group, `hub-cluster-node-*`. The cluster SG
# (`eks-cluster-sg-*`) is NOT attached to them, so allowing it would produce a
# rule that looks correct and passes no traffic. With the AWS VPC CNI a pod's
# ENI inherits the node's groups, so this is the source address Argo's
# connections actually arrive from.
data "aws_security_groups" "eks_nodes" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  filter {
    name   = "group-name"
    values = ["${var.eks_cluster_name}-node-*"]
  }
}

# Amazon Linux 2023, resolved from SSM so it tracks patches instead of pinning
# a stale AMI id. x86_64 deliberately: the addon charts this fleet exists to
# test are not all guaranteed multi-arch, and an arm64-only image pull failure
# would read as an addon defect rather than an infrastructure choice.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
