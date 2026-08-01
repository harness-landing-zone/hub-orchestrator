data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

data "aws_iam_roles" "eks_admin_role" {
  name_regex = "AWSReservedSSO_AWSPowerUserAccess_.*"
}
