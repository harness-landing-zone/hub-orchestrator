
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    # Same reason as the kubernetes provider below - no aws binary on the
    # runner. Unused today (no helm resources), fixed anyway so the next
    # person to add one does not rediscover this the hard way.
    token = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  # Token generated IN-PROVIDER rather than by shelling out to `aws eks
  # get-token`. The Harness IaCM runner image ships no aws binary, so the exec
  # form fails with "executable aws not found" the moment any kubernetes
  # resource is applied. This path reuses the AWS provider's own credentials -
  # here the OIDC role the runner already assumed - and needs no CLI.
  token = data.aws_eks_cluster_auth.this.token
}

provider "aws" {
  region = "eu-west-2"
}

provider "harness" {
  endpoint         = var.harness_endpoint
  account_id       = var.harness_account_id
  platform_api_key = var.harness_api_token
}

# terraform {
#   backend "s3" {
#     bucket         = "mk-backend-bucket"
#     key            = "gitops-hub/terraform.tfstate"
#     region         = "eu-west-2"
#   }
# }