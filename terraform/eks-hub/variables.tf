################################################################################
# Infrastructure Variables
################################################################################
variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the hub VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all AZs (cost saving for non-prod)"
  type        = bool
  default     = true
}

################################################################################
# Cluster Related Variables
################################################################################
variable "eks_cluster_endpoint_public_access" {
  description = "Deploying public or private endpoint for the cluster"
  type        = bool
  default     = true
}

variable "managed_node_group_ami" {
  description = "The ami type of managed node group"
  type        = string
  default     = "BOTTLEROCKET_x86_64"
}

variable "managed_node_group_instance_types" {
  description = "List of managed node group instances"
  type        = list(string)
  default     = ["m5.xlarge"]
}

variable "ami_release_version" {
  description = "The AMI version of the Bottlerocket worker nodes"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
}

variable "tenant" {
  type        = string
  description = "Type of tenancy — control-plane for hub, tenant name for spoke"
}

variable "fleet_member" {
  description = "Fleet membership type of the cluster (hub or spoke)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
  default     = "gitops-hub-cluster"
}

variable "enable_automode" {
  description = "Enabling Automode Cluster"
  type        = bool
  default     = false
}

variable "aws_resources" {
  description = "Feature flags for AWS resource creation (pod identities, addons)"
  type        = any
  default     = {}
}

# Declared as a FLAT root variable rather than a key inside aws_resources
# because Harness IaCM passes each workspace variable as its own `-var`, and an
# object-typed variable cannot be set that way from a single workspace field.
# Assigning it without this block fails the plan outright:
#   Error: Value for undeclared variable ... assigned on the command line
variable "external_secrets_create_permission" {
  description = "Allow the External Secrets controller to CREATE secrets in Secrets Manager, not only read them. Required for PushSecret, which is how a credential generated in-cluster (a Grafana admin password, for example) is published so it survives a cluster rebuild. Scope is still limited to the cluster-prefixed ARNs in pod-identity.tf; this does not grant account-wide write."
  type        = bool
  # FALSE by default, matching the upstream module. The consequence is worth
  # stating: remove the workspace variable and the permission silently goes
  # away, PushSecret starts failing AccessDenied, and the symptom surfaces in
  # external-secrets rather than anywhere near terraform.
  default = false
}

variable "environment" {
  description = "The environment of the Hub cluster"
  type        = string
}

################################################################################
# Git Repository Variables
################################################################################
variable "git_org_name" {
  description = "The name of the Github organisation"
  type        = string
  default     = ""
}

variable "gitops_fleet_repo_name" {
  description = "The fleet Git repository name"
  type        = string
  default     = ""
}

variable "gitops_fleet_repo_path" {
  description = "Path within the fleet repository"
  type        = string
  default     = ""
}

variable "gitops_fleet_repo_base_path" {
  description = "Base path within the fleet repository"
  type        = string
  default     = ""
}

variable "gitops_fleet_repo_revision" {
  description = "Git revision (branch/tag) for the fleet repository"
  type        = string
  default     = "main"
}

################################################################################
# Harness GitOps Variables
################################################################################
variable "harness_account_id" {
  description = "Harness account ID"
  type        = string
}

variable "harness_org_id" {
  description = "Harness organisation ID"
  type        = string
  default     = "default"
}

variable "harness_project_id" {
  description = "Harness project ID (leave empty for Org-level scope)"
  type        = string
  default     = ""
}

variable "harness_api_token" {
  description = "Harness platform API token (set via TF_VAR_harness_api_token env var)"
  type        = string
  sensitive   = true
}

variable "harness_endpoint" {
  description = "Harness API gateway endpoint"
  type        = string
  default     = "https://app.harness.io/gateway"
}

variable "create_harness_agent" {
  description = "Whether to create the Harness GitOps agent and its related resources (agent, namespace, in-cluster registration, fleet repo, bootstrap ApplicationSet). Set to false to provision the cluster without the agent."
  type        = bool
  default     = true
}

variable "harness_agent_identifier" {
  description = "Identifier for the Harness GitOps agent on the hub cluster"
  type        = string
  default     = "hub-agent"
}

variable "harness_agent_name" {
  description = "Display name for the Harness GitOps agent on the hub cluster"
  type        = string
  default     = "hub-agent"
}

variable "harness_agent_namespace" {
  description = "Kubernetes namespace for the Harness GitOps agent"
  type        = string
  default     = "harness-agent"
}


################################################################################
# Argo CD cluster-config secret (see harness_cluster_secret.tf)
################################################################################

variable "argo_cluster_secret_identifier" {
  description = "Identifier of the Harness secret holding this cluster's Argo CD config JSON, base64-encoded."
  type        = string
  default     = "eks_hub_cluster_config"
}

variable "argo_cluster_secret_org_id" {
  description = "Harness org owning the Argo cluster-config secret. This is NOT harness_org_id: that one scopes the (currently disabled) agent resources, while this must be the org whose project is mapped to the AppProject the consuming Argo Application runs under, or the plugin cannot resolve the expression."
  type        = string
  default     = "harness_controllers"
}

variable "argo_cluster_secret_project_id" {
  description = "Harness project owning the Argo cluster-config secret. Must match the Harness project mapped to the consuming AppProject."
  type        = string
  default     = "hub_orchistrator"
}

variable "argo_assume_role_arn" {
  description = "IAM role ARN the CONSUMING Argo instance assumes to reach this cluster (renders awsAuthConfig). Empty omits the block. Requires a matching EKS access entry AND an AWS identity on the consumer, so leave empty until the hub can federate into AWS."
  type        = string
  default     = ""
}

variable "argo_bearer_token" {
  description = "ServiceAccount token the CONSUMING Argo instance uses to reach this cluster (renders bearerToken). Empty omits the block. Use this when the consumer has no AWS identity - it needs nothing on the AWS side."
  type        = string
  default     = ""
  sensitive   = true
}

################################################################################
# Remote Argo CD access (see argo_remote_access.tf)
################################################################################

variable "create_argo_access" {
  description = "Create a ServiceAccount + ClusterRoleBinding + non-expiring token Secret so an EXTERNAL Argo CD (one with no AWS identity) can reach this cluster. Leave false when this cluster runs its own agent and pulls from git - then nothing needs to reach in."
  type        = bool
  default     = false
}

variable "argo_access_namespace" {
  description = "Namespace holding the remote-access ServiceAccount and its token Secret."
  type        = string
  default     = "kube-system"
}

variable "argo_access_service_account" {
  description = "Name of the remote-access ServiceAccount. Also names the ClusterRoleBinding and the token Secret."
  type        = string
  default     = "argocd-manager"
}

variable "argo_access_cluster_role" {
  description = "ClusterRole bound to the remote-access ServiceAccount. cluster-admin matches what `argocd cluster add` grants; scope it down if the consuming Argo only manages known namespaces."
  type        = string
  default     = "cluster-admin"
}
