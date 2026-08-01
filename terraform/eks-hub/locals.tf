locals {
  cluster_name    = var.cluster_name
  cluster_info = {
    cluster_name                       = module.eks.cluster_name
    cluster_endpoint                   = module.eks.cluster_endpoint
    cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
    cluster_arn                        = module.eks.cluster_arn
  }
  enable_automode = var.enable_automode
  environment     = var.environment
  fleet_member    = var.fleet_member
  tenant          = var.tenant
  region          = data.aws_region.current.id
  cluster_version = var.kubernetes_version
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)

  gitops_fleet_repo_url = "https://github.com/${var.git_org_name}/${var.gitops_fleet_repo_name}.git"

  external_secrets = {
    namespace       = "external-secrets"
    service_account = "external-secrets-sa"
  }

  aws_load_balancer_controller = {
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller-sa"
  }

  karpenter = {
    namespace       = "kube-system"
    service_account = "karpenter"
    role_name       = "karpenter-${local.cluster_name}"
  }

  aws_resources = {
    enable_external_secrets             = try(var.aws_resources.enable_external_secrets, false)
    enable_aws_lb_controller            = try(var.aws_resources.enable_aws_lb_controller, false)
    enable_karpenter                    = try(var.aws_resources.enable_karpenter, false)
    enable_cni_metrics_helper           = try(var.aws_resources.enable_cni_metrics_helper, false)
    enable_aws_cloudwatch_observability = try(var.aws_resources.enable_aws_cloudwatch_observability, false)
    enable_aws_load_balancer_controller = try(var.aws_resources.enable_aws_load_balancer_controller, false)
  }

  addons = merge(
    { tenant = local.tenant },
    { fleet_member = local.fleet_member },
    { kubernetes_version = local.cluster_version },
    { aws_cluster_name = module.eks.cluster_name },
  )

  addons_metadata = merge(
    {
      tenant           = local.tenant
      aws_cluster_name = module.eks.cluster_name
      aws_region       = local.region
      aws_account_id   = data.aws_caller_identity.current.account_id
      aws_vpc_id       = module.vpc.vpc_id
    },
    {
      gitops_agent_namespace = var.harness_agent_namespace
    },
    {
      fleet_repo_url      = local.gitops_fleet_repo_url
      fleet_repo_path     = var.gitops_fleet_repo_path
      fleet_repo_basepath = var.gitops_fleet_repo_base_path
      fleet_repo_revision = var.gitops_fleet_repo_revision
    },
    {
      karpenter_namespace          = local.karpenter.namespace
      karpenter_service_account    = local.karpenter.service_account
      karpenter_node_iam_role_name = try(module.karpenter[0].node_iam_role_name, null)
      karpenter_sqs_queue_name     = try(module.karpenter[0].queue_name, null)
    },
    {
      external_secrets_namespace       = local.external_secrets.namespace
      external_secrets_service_account = local.external_secrets.service_account
    },
    {
      aws_load_balancer_controller_namespace       = local.aws_load_balancer_controller.namespace
      aws_load_balancer_controller_service_account = local.aws_load_balancer_controller.service_account
    }
  )

  tags = {
    Blueprint = local.cluster_name
  }
}
