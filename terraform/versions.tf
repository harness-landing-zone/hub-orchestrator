# Only the Harness provider here. The fleet module in hga-bootstrap needs
# OpenTofu >= 1.9 for provider for_each (one kubernetes provider per spoke);
# this root manages a single Harness secret and no clusters, so it carries
# neither that constraint nor the kubernetes provider.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    harness = {
      source  = "harness/harness"
      version = ">= 0.31.0"
    }
  }
}
