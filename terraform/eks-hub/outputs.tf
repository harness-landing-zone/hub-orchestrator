################################################################################
# What the fleet member file needs
#
# The Harness secret carries only the CREDENTIAL half of the Argo cluster
# Secret. name and server are not secret and live in git, in the member file the
# hub's fleet ApplicationSet reads - so surface them here rather than making
# someone dig them out of the console or the state.
################################################################################

output "cluster_endpoint" {
  description = "EKS API endpoint. Goes in the fleet member file as `server`."
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name. NOTE: this is the name in AWS and in this cluster's OWN Argo. The consuming hub must register it under a DIFFERENT name if that hub already uses this one for itself."
  value       = module.eks.cluster_name
}

output "argo_cluster_secret_identifier" {
  description = "Identifier of the Harness secret holding the base64 Argo cluster config. Reference it as <+secrets.getValue('<id>')> from a chart rendered by the ArgoCD Harness Plugin."
  value       = harness_platform_secret_text.argo_cluster_config.identifier
}

output "argo_remote_access_enabled" {
  description = "Whether a ServiceAccount token was minted for an external Argo CD. False means the cluster-config secret carries CA metadata only and no consumer can authenticate with it."
  value       = var.create_argo_access
}
