################################################################################
# The GitHub App PRIVATE KEY only, as its own secret.
#
# WHY THIS EXISTS ALONGSIDE github_app:
# the single-JSON `github_app` secret works for Harness CD, which resolves
# expressions in a fetched values file BEFORE helm runs - so the chart receives
# real JSON and can fromJson it.
#
# The ArgoCD Harness Plugin cannot do that. It substitutes into helm's OUTPUT,
# so at template time the chart still sees the literal `<+secrets.getValue(...)>`
# string, `fromJson` fails, and the whole render dies with "not valid JSON".
# The chart's INDIVIDUAL githubApp* fields are passed straight through without
# parsing, so expressions survive to substitution. Hence this second form.
#
# Same source value as github_app's githubAppPrivateKeyB64 key, so the two
# forms cannot drift.
#
# WHY ONLY THE KEY, AND NOT THE TWO IDS:
# app_id and installation_id are NOT credentials - both appear in the GitHub
# App's own URL - so they live as literals in the member file instead. That is
# not tidiness, it is the fail-closed property:
#
#   - the private key lands in the Secret's data: block, which must be valid
#     base64. An expression that is NOT substituted is not valid base64, so the
#     API server rejects the Secret rather than writing a broken credential.
#   - the two ids land in stringData, which has NO such guard. An unresolved
#     expression there is written verbatim and surfaces later as an opaque
#     GitHub auth failure.
#
# So the only value that can fail here fails closed, and the two that could
# fail open are not expressions at all.
################################################################################

locals {
  github_app_tags = ["managed-by:hub-orchestrator-terraform", "tier:bootstrap-0", "form:split"]
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
