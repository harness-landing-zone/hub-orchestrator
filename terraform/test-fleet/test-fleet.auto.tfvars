################################################################################
# Placement - must match the eks-hub workspace's own tfvars
################################################################################
region           = "eu-west-2"
vpc_name         = "hub-cluster"
eks_cluster_name = "hub-cluster"

################################################################################
# Instance
#
# Small on purpose: this fleet exists to prove progressive registration and
# rollout, not to run the monitoring stack three times over. Bump to t3.xlarge
# if kube-prometheus-stack ever has to land on all three clusters.
################################################################################
name             = "k3d-test-fleet"
instance_type    = "t3.large"
root_volume_size = 60

clusters = [
  { name = "k3d-1", api_port = 6551 },
  { name = "k3d-2", api_port = 6552 },
  { name = "k3d-3", api_port = 6553 },
]

################################################################################
# Cost guard - stops (never terminates) the box each evening
################################################################################
auto_stop_enabled  = true
auto_stop_cron     = "cron(0 20 * * ? *)"
auto_stop_timezone = "Europe/London"
