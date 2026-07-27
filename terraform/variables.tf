variable "harness_account_id" {
  description = "Harness account identifier."
  type        = string
  default     = "qIYsos1ZQO6fJMG1Ip6KJA"
}

variable "org_id" {
  description = "Harness organization holding the hub entities."
  type        = string
  default     = "harness_controllers"
}

variable "project_id" {
  description = "Harness project holding the hub entities."
  type        = string
  default     = "hub_orchistrator"
}

variable "secret_manager" {
  description = "Secret manager identifier used for the inline secret."
  type        = string
  default     = "harnessSecretManager"
}

variable "github_app" {
  description = <<-EOT
    GitHub App credential for the bootstrap repository. Creates ONE project
    secret, github_app, holding a single-line JSON object
    {githubAppID, githubAppInstallationID, githubAppPrivateKeyB64} - ids as
    strings, private key base64.

    Single-line and base64 are both load-bearing. account-agent-day0.yaml
    resolves the whole secret into the bootstrap chart's
    gitSecret.githubAppJson, and an expression resolved inside a fetched
    values file cannot span lines - a raw multi-line PEM would break the
    YAML. The chart then writes the base64 straight into the Secret's data:
    block, which is already base64 by definition, so nothing re-encodes it.

    private_key_pem_file is the path to the RAW .pem downloaded from the
    GitHub App settings page. Do NOT pre-encode it: base64encode() below
    does that, and a pre-encoded file yields a double-encoded key that fails
    later as an opaque auth error rather than a decode error.
  EOT
  type = object({
    app_id               = string
    installation_id      = string
    private_key_pem_file = string
  })

  validation {
    condition     = can(regex("^[0-9]+$", var.github_app.app_id))
    error_message = "github_app.app_id must be the numeric GitHub App ID, quoted as a string."
  }
  validation {
    condition     = can(regex("^[0-9]+$", var.github_app.installation_id))
    error_message = "github_app.installation_id must be the numeric installation ID, quoted as a string."
  }
}
