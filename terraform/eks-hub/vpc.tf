################################################################################
# Hub VPC
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 4)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Subnet tags required for EKS and load balancer discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                          = 1
    "kubernetes.io/cluster/${local.cluster_name}"     = "owned"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                 = 1
    "kubernetes.io/cluster/${local.cluster_name}"     = "owned"
  }

  intra_subnet_tags = {
    "kubernetes.io/role/cni"       = 1
    "karpenter.sh/discovery"       = local.cluster_name
  }

  tags = local.tags
}
