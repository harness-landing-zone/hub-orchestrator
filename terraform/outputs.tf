output "github_app_secret" {
  description = "Identifier of the GitHub App credential secret (name only, never the value)."
  value       = harness_platform_secret_text.github_app.identifier
}

output "github_app_secret_ref" {
  description = "How account-agent-day0.yaml refers to it."
  value       = "<+secrets.getValue(\"${harness_platform_secret_text.github_app.identifier}\")>"
}
