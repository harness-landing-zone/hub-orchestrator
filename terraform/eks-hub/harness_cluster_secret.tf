################################################################################
# Argo CD cluster CONFIG as a Harness secret
#
# This is what lets the hub's Argo CD register this cluster as a destination.
# The fleet-members-registration chart renders an argocd secret-type=cluster
# Secret and pulls this value in through the ArgoCD Harness Plugin.
#
# WHY THE BUILT-IN SECRET MANAGER, NOT THE AWS ONE:
# the plugin resolves <+secrets.getValue()> during Argo CD manifest generation
# with NO delegate in the loop, so it can only decrypt secrets whose material
# Harness itself holds - Harness Secret Manager or HashiCorp Vault. An
# AWS-Secrets-Manager-backed secret fails there with
#   failed to decrypt secret <id>: unsupported encryption type AWS_SECRETS_MANAGER
# (reproduced live on the hub, 2026-08-01). The ASM copy in eks.tf stays as the
# source of truth for AWS-side consumers such as ESO on this cluster; this is a
# second, plugin-readable copy of the credential half only.
#
# WHY BASE64:
# the value lands in a Kubernetes Secret's data: field. The plugin substitutes
# textually into the ALREADY-RENDERED manifest, so a raw JSON value - which is
# full of double quotes - would break the surrounding YAML. Base64 has no
# YAML-significant characters. It also fails CLOSED: an expression that is not
# substituted is not valid base64, so the API server rejects the Secret rather
# than writing a malformed cluster Secret. That matters because the
# ApplicationSet controller parses EVERY cluster Secret when it lists clusters,
# so one bad one halts ALL ApplicationSet reconciliation.
################################################################################

locals {
  # A token minted by argo_remote_access.tf wins; var.argo_bearer_token stays
  # as the escape hatch for a token created outside this module.
  argo_bearer_token_effective = var.create_argo_access ? kubernetes_secret.argo_manager_token[0].data["token"] : var.argo_bearer_token

  # Only the credential half of the Argo cluster Secret. name, server, labels
  # and annotations are not secret and belong in the fleet member file in git.
  argo_cluster_config = merge(
    {
      tlsClientConfig = {
        insecure = false
        caData   = module.eks.cluster_certificate_authority_data
      }
    },
    var.argo_assume_role_arn != "" ? {
      awsAuthConfig = {
        clusterName = module.eks.cluster_name
        roleARN     = var.argo_assume_role_arn
      }
    } : {},
    local.argo_bearer_token_effective != "" ? {
      bearerToken = local.argo_bearer_token_effective
    } : {}
  )
}

resource "harness_platform_secret_text" "argo_cluster_config" {
  identifier  = var.argo_cluster_secret_identifier
  name        = var.argo_cluster_secret_identifier
  description = "Argo CD cluster config JSON (base64) for ${local.cluster_name}. Consumed by fleet-members-registration via the ArgoCD Harness Plugin."
  tags        = ["managed-by:hub-terraform", "cluster:${local.cluster_name}"]

  org_id     = var.argo_cluster_secret_org_id
  project_id = var.argo_cluster_secret_project_id

  # Must stay harnessSecretManager - see the header note. Pointing this at the
  # AWS Secrets Manager connector would store the value in AWS and make it
  # unreadable to the plugin, even with value_type = "Inline".
  secret_manager_identifier = "harnessSecretManager"
  value_type                = "Inline"
  value                     = base64encode(jsonencode(local.argo_cluster_config))
}
