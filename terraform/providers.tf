# Auth: export HARNESS_PLATFORM_API_KEY before running - never put the key
# in code, tfvars, or state inputs.
provider "harness" {
  endpoint   = "https://app.harness.io/gateway"
  account_id = var.harness_account_id
}
