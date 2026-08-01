# terraform {
#   backend "http" {
#     address = "https://app.harness.io/gateway/iacm/api/orgs/harness_controllers/projects/hub_orchistrator/workspaces/ekshubcluster/terraform-backend?accountIdentifier=qIYsos1ZQO6fJMG1Ip6KJA"
#     username = "harness"
#     lock_address = "https://app.harness.io/gateway/iacm/api/orgs/harness_controllers/projects/hub_orchistrator/workspaces/ekshubcluster/terraform-backend/lock?accountIdentifier=qIYsos1ZQO6fJMG1Ip6KJA"
#     lock_method = "POST"
#     unlock_address = "https://app.harness.io/gateway/iacm/api/orgs/harness_controllers/projects/hub_orchistrator/workspaces/ekshubcluster/terraform-backend/lock?accountIdentifier=qIYsos1ZQO6fJMG1Ip6KJA"
#     unlock_method = "DELETE"
#   }
# }