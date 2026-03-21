# Root-level outputs — surface the most commonly needed values after apply.
# Run `terraform output` to retrieve these without re-reading state.

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint. Used by kubectl and CI/CD pipelines."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA data for the cluster. Required when configuring the Kubernetes Terraform provider."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the cluster OIDC provider. Pass this when creating IRSA IAM roles."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "ID of the VPC hosting the cluster."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Ordered list of private subnet IDs used by the node group."
  value       = module.vpc.private_subnet_ids_list
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role assumed by worker nodes."
  value       = module.eks.node_iam_role_arn
}
