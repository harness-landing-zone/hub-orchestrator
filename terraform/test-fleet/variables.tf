################################################################################
# Placement
#
# This workspace CONSUMES the VPC that terraform/eks-hub owns - it never
# creates network. That separation is the whole point of a second workspace:
# `tofu destroy` here can never reach the hub's VPC, subnets or NAT.
################################################################################

variable "region" {
  description = "AWS region. Must be the region eks-hub runs in - the fleet is reachable by VPC routing, not over the internet."
  type        = string
  default     = "eu-west-2"
}

variable "vpc_name" {
  description = "Name tag of the VPC that eks-hub lives in. Looked up, never created here."
  type        = string
  default     = "hub-cluster"
}

variable "eks_cluster_name" {
  description = "EKS cluster whose NODE security group is allowed to reach the k3d API ports. With the VPC CNI, Argo's pods egress through their node's ENI, so the node SG - not the cluster SG - is the real source."
  type        = string
  default     = "hub-cluster"
}

################################################################################
# Instance
################################################################################

variable "name" {
  description = "Name prefix for every resource in this workspace."
  type        = string
  default     = "k3d-test-fleet"
}

variable "instance_type" {
  description = <<-EOT
    Sized for THREE single-node k3d clusters plus light addons, not for the full
    monitoring stack. Rough budget at t3.large (8 GiB):
      3 x k3s server  ~2.4 GiB
      OS + docker     ~1.0 GiB
      addons headroom ~4.0 GiB
    kube-prometheus-stack is ~2.5 GiB PER CLUSTER, so if this fleet ever has to
    run monitoring on all three, move to t3.xlarge or larger. It is one apply.
  EOT
  type        = string
  default     = "t3.large"
}

variable "root_volume_size" {
  description = "GiB. Holds every container image for three clusters; 60 leaves plenty of room and costs a few dollars a month even while the instance is stopped."
  type        = number
  default     = 60
}

variable "clusters" {
  description = <<-EOT
    The k3d clusters to create, and the host port each publishes its API on.

    PORTS ARE FIXED ON PURPOSE. k3d's default is a random high port chosen by
    Docker, which changes on every recreate - and a cluster registered in Argo
    by address would break silently every time the fleet was rebuilt. Fixed
    ports make registration survive a `k3d cluster delete && create`.
  EOT
  type = list(object({
    name     = string
    api_port = number
  }))
  default = [
    { name = "k3d-1", api_port = 6551 },
    { name = "k3d-2", api_port = 6552 },
    { name = "k3d-3", api_port = 6553 },
  ]
}

variable "extra_ingress_cidrs" {
  description = "Additional CIDRs allowed to reach the k3d API ports. Empty by default: the EKS node SG rule is the only access, so nothing in the VPC can reach these API servers by accident."
  type        = list(string)
  default     = []
}

################################################################################
# Cost guard
#
# This fleet is for proving a chart version and then going away. The schedule
# below is the backstop for the run that gets forgotten - it STOPS the instance
# (never terminates it), so the k3d clusters come back intact on next start via
# the k3d-fleet systemd unit.
################################################################################

variable "auto_stop_enabled" {
  description = "Create a scheduled stop for the instance. Leave true unless you deliberately want the fleet online overnight."
  type        = bool
  default     = true
}

variable "auto_stop_cron" {
  description = "When to stop the instance, in EventBridge Scheduler cron syntax, evaluated in auto_stop_timezone."
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "auto_stop_timezone" {
  description = "Timezone for auto_stop_cron."
  type        = string
  default     = "Europe/London"
}

variable "tags" {
  description = "Applied to everything, so one tag filter finds the whole fleet when it is time to clean up."
  type        = map(string)
  default = {
    Blueprint = "k3d-test-fleet"
    Purpose   = "addons-progressive-rollout-testing"
    Ephemeral = "true"
  }
}
