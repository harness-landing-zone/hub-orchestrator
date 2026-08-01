
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = [
        "eks",
        "get-token",
        "--cluster-name", module.eks.cluster_name,
        "--region", local.region
      ]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  # insecure = true
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = [
      "eks",
      "get-token",
      "--cluster-name", module.eks.cluster_name,
      "--region", local.region
    ]
  }
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