provider "aws" {
  region = var.region
}

# Local state, deliberately - same as the eks-hub workspace, whose backend
# blocks are also commented out. This fleet is disposable by design; losing its
# state costs a `tofu import` of one instance, not a cluster.
