# GitHub App hand-off for the day-0 bootstrap repository credential.
#
# ONE secret carrying the whole credential as a single-line JSON object.
# values/account-agent-day0.yaml resolves it into the bootstrap chart's
# gitSecret.githubAppJson, and the chart renders both the Argo CD repository
# Secret and its global repo-creds companion from it, so the account agent can
# pull this repo from the moment it installs.
#
# One secret instead of three because an expression resolved inside a fetched
# values file must stay single-line - JSON plus base64 keeps the whole
# credential injectable in one piece.
#
# jsonencode() is doing more work than it looks: it emits the two ids as JSON
# STRINGS. The chart hard-fails on numbers (bootstrap-repo.yaml, kindIs
# "string") because an unquoted 7+ digit number renders in scientific notation
# and produces a credential that is silently wrong.
#
# Lifted from hga-bootstrap/terraform rather than reused in place: that root
# is the demo fleet's, and its state gets rebuilt and broken during workshops.
# bootstrap-0 keeps its own state for the same reason this repo is separate.
resource "harness_platform_secret_text" "github_app" {
  identifier                = "github_app"
  name                      = "github_app"
  description               = "GitHub App credential for the bootstrap (hub-orchestrator) repo - JSON: githubAppID, githubAppInstallationID, githubAppPrivateKeyB64."
  tags                      = ["managed-by:hub-orchestrator-terraform", "tier:bootstrap-0"]
  org_id                    = var.org_id
  project_id                = var.project_id
  secret_manager_identifier = var.secret_manager
  value_type                = "Inline"

  value = jsonencode({
    githubAppID             = var.github_app.app_id
    githubAppInstallationID = var.github_app.installation_id
    githubAppPrivateKeyB64  = base64encode(file(pathexpand(var.github_app.private_key_pem_file)))
  })
}
