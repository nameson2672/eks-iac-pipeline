# Cluster
output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL of the Kubernetes API server. Used by kubectl and Helm providers."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster. Required by the Kubernetes / Helm Terraform providers."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version running on the EKS control plane (as reported by AWS)."
  value       = aws_eks_cluster.this.version
}

output "cluster_oidc_issuer_url" {
  description = "OpenID Connect issuer URL for the cluster. Use this to configure IAM Roles for Service Accounts (IRSA)."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider. Required for creating IRSA IAM roles for workloads (Load Balancer Controller, Cluster Autoscaler, etc.)."
  value       = aws_iam_openid_connect_provider.this.arn
}


# Security Groups
output "cluster_security_group_id" {
  description = "ID of the security group attached to the EKS control-plane ENIs."
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "ID of the security group attached to every worker node in the managed node group."
  value       = aws_security_group.nodes.id
}


# IAM
output "cluster_iam_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "cluster_iam_role_name" {
  description = "Name of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.name
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role assumed by worker nodes. Pass this to aws-auth ConfigMap entries or Pod Identity associations."
  value       = aws_iam_role.nodes.arn
}

output "node_iam_role_name" {
  description = "Name of the IAM role assumed by worker nodes."
  value       = aws_iam_role.nodes.name
}


# Managed Node Group
output "node_group_arn" {
  description = "ARN of the managed node group."
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Current status of the managed node group (e.g. ACTIVE, CREATING, DEGRADED)."
  value       = aws_eks_node_group.this.status
}

output "node_group_resources" {
  description = "List of objects describing resources associated with the node group, including Auto Scaling Group names and remote access security group IDs."
  value       = aws_eks_node_group.this.resources
}
