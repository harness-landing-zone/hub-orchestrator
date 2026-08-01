################################################################################
# Bearer-token access for a REMOTE Argo CD
#
# WHY A TOKEN AND NOT awsAuthConfig:
# the hub that bootstraps this cluster is a k3s box with no AWS identity. It
# cannot assume an IAM role, so awsAuthConfig is simply unavailable to it. The
# EKS API server authenticates ServiceAccount tokens natively - that is core
# Kubernetes, not IAM - so a SA token lets a credential-less consumer in
# without teaching it anything at all about AWS. This is the same shape
# `argocd cluster add` produces for any non-EKS cluster.
#
# OPT-IN, because it is not always needed: if this cluster runs its OWN agent
# and pulls from git (the pull model), nothing outside it needs to reach in and
# none of this should be created. Only enable it when something external must
# connect.
#
# THE TRADE-OFF, stated plainly rather than buried:
#   - this mints a LONG-LIVED, high-privilege credential that leaves the cluster
#   - the kubernetes provider stores secret data in OpenTofu state as PLAIN TEXT
#     (and this workspace has prune_sensitive_data = false)
#   - rotation means deleting and recreating; revocation means deleting the SA
# Prefer the pull model, or IAM + an EKS access entry, when either is available.
################################################################################

resource "kubernetes_service_account" "argo_manager" {
  count = var.create_argo_access ? 1 : 0

  metadata {
    name      = var.argo_access_service_account
    namespace = var.argo_access_namespace
  }
}

resource "kubernetes_cluster_role_binding" "argo_manager" {
  count = var.create_argo_access ? 1 : 0

  metadata {
    name = var.argo_access_service_account
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = var.argo_access_cluster_role
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argo_manager[0].metadata[0].name
    namespace = var.argo_access_namespace
  }
}

resource "kubernetes_secret" "argo_manager_token" {
  count = var.create_argo_access ? 1 : 0

  metadata {
    name      = "${var.argo_access_service_account}-token"
    namespace = var.argo_access_namespace
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.argo_manager[0].metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"

  # Defaults to true, stated explicitly because the whole design hangs on it:
  # the token controller populates .data AFTER the object is created, so
  # without the wait the Harness secret below would be built from an empty
  # token and the cluster would register with a credential that never works.
  wait_for_service_account_token = true
}
