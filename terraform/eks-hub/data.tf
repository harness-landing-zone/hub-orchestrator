data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

data "aws_iam_roles" "eks_admin_role" {
  name_regex = "AWSReservedSSO_AWSPowerUserAccess_.*"
}

# Short-lived EKS token for the kubernetes/helm providers, generated from the
# AWS provider's credentials. Replaces the `aws eks get-token` exec plugin,
# which cannot work on the Harness IaCM runner (no aws binary in the image).
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
