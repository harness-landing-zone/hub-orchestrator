################################################################################
# The SAME GitHub App credential, emitted as three separate secrets.
#
# WHY BOTH FORMS EXIST:
# the single-JSON `github_app` secret works for Harness CD, which resolves
# expressions in a fetched values file BEFORE helm runs - so the chart receives
# real JSON and can fromJson it.
#
# The ArgoCD Harness Plugin cannot do that. It substitutes into helm's OUTPUT,
# so at template time the chart still sees the literal `<+secrets.getValue(...)>`
# string, `fromJson` fails, and the whole render dies with "not valid JSON".
# The chart's INDIVIDUAL githubApp* fields are passed straight through without
# parsing, so expressions survive to substitution. Hence three secrets.
#
# Same source values as github_app, so the two forms cannot drift.
#
# FAIL-CLOSED PROPERTY: the private key lands in the Secret's data: block, which
# must be valid base64. An expression that is NOT substituted is not valid
# base64, so the API server rejects the Secret rather than writing a broken
# credential. The two ids land in stringData and have no such guard - an
# unresolved one would produce an opaque GitHub auth failure instead.
################################################################################

locals {
  github_app_tags = ["managed-by:hub-orchestrator-terraform", "tier:bootstrap-0", "form:split"]
}

resource "harness_platform_secret_text" "github_app_id" {
  identifier                = "github_app_id"
  name                      = "github_app_id"
  description               = "GitHub App ID for the bootstrap repo. Split form of github_app, for plugin-rendered charts. Quoted string - a 7+ digit unquoted number renders in scientific notation and silently produces a wrong credential."
  tags                      = local.github_app_tags
  org_id                    = var.org_id
  project_id                = var.project_id
  secret_manager_identifier = var.secret_manager
  value_type                = "Inline"

  value = var.github_app.app_id
}

resource "harness_platform_secret_text" "github_app_installation_id" {
  identifier                = "github_app_installation_id"
  name                      = "github_app_installation_id"
  description               = "GitHub App installation ID for the bootstrap repo. Split form of github_app, for plugin-rendered charts."
  tags                      = local.github_app_tags
  org_id                    = var.org_id
  project_id                = var.project_id
  secret_manager_identifier = var.secret_manager
  value_type                = "Inline"

  value = var.github_app.installation_id
}

resource "harness_platform_secret_text" "github_app_private_key_b64" {
  identifier                = "github_app_private_key_b64"
  name                      = "github_app_private_key_b64"
  description               = "GitHub App private key, base64 of the RAW pem. Split form of github_app, for plugin-rendered charts. Base64 keeps it single-line and makes an unresolved expression fail closed in the Secret's data block."
  tags                      = local.github_app_tags
  org_id                    = var.org_id
  project_id                = var.project_id
  secret_manager_identifier = var.secret_manager
  value_type                = "Inline"

  # Identical expression to github_app's githubAppPrivateKeyB64 key. Do NOT
  # pre-encode the file: a pre-encoded pem yields a double-encoded key that
  # surfaces later as an opaque auth error, not a decode error.
  value = base64encode(file(pathexpand(var.github_app.private_key_pem_file)))
}
