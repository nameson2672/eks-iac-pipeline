
# Locals

locals {
  node_group_name = coalesce(var.node_group_name, "${var.name}-nodes")

  # All IAM policies required by the managed node group — iterated with for_each
  # so a single resource block handles every attachment cleanly.
  node_iam_policies = {
    worker_node = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    cni         = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    ecr         = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }
}

# IAM — EKS Control Plane
#
# The cluster role trusts eks.amazonaws.com and is granted the minimum policy
# required to manage VPC resources, ENIs, and the Kubernetes control plane.

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  # Ensure the role is fully replaced before the old one is deleted so that
  # any brief gap between destroy and create does not break a live cluster.
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# Optional: attach AmazonEKSVPCResourceController if you plan to use
# Security Groups for Pods (SGP). Uncomment the block below when needed.
#
# resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
#   role       = aws_iam_role.cluster.name
# }

# IAM — Managed Node Group
#
# EC2 worker nodes assume this role. The three policies cover:
#   • AmazonEKSWorkerNodePolicy          — node registration, describe APIs
#   • AmazonEKS_CNI_Policy               — VPC CNI plugin (IP assignment)
#   • AmazonEC2ContainerRegistryReadOnly — pull images from ECR

data "aws_iam_policy_document" "nodes_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodes" {
  name               = "${var.name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.nodes_assume_role.json

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-node-role"
  })
}

# Attach all three required node policies in a single resource block.
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each = local.node_iam_policies

  policy_arn = each.value
  role       = aws_iam_role.nodes.name
}

# Security Group — EKS Control Plane
#
# Attached to the control-plane ENIs that EKS places inside your VPC.
# Rules allow the API server to receive requests from worker nodes (443) and
# to initiate connections back to them (kubelet, ephemeral ports).

resource "aws_security_group" "cluster" {
  name        = "${var.name}-cluster-sg"
  description = "Security group attached to the EKS control-plane ENIs for cluster ${var.name}."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-cluster-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: worker nodes → API server (kubectl, kubelet bootstrap, webhooks)
resource "aws_security_group_rule" "cluster_ingress_nodes_443" {
  description              = "Allow worker nodes to reach the Kubernetes API server on port 443."
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.nodes.id
  security_group_id        = aws_security_group.cluster.id
}

# Egress: control plane → nodes (kubelet, exec/logs/port-forward, etc.)
resource "aws_security_group_rule" "cluster_egress_all" {
  description       = "Allow all outbound traffic from the control plane."
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
}

# Security Group — Worker Nodes
#
# Attached to every EC2 instance in the managed node group. Rules allow:
#   • Node-to-node: unrestricted (pod traffic, overlay networking)
#   • Control plane → kubelet API (10250): health checks, exec, logs
#   • Control plane → ephemeral ports (1025-65535): exec/port-forward tunnels
#   • Egress: unrestricted (pull images, reach AWS APIs, internet if needed)

resource "aws_security_group" "nodes" {
  name        = "${var.name}-nodes-sg"
  description = "Security group attached to worker nodes for EKS cluster ${var.name}."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                = "${var.name}-nodes-sg"
    "kubernetes.io/cluster/${var.name}" = "owned"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: node ↔ node (pod-to-pod, overlay networking, CNI health checks)
resource "aws_security_group_rule" "nodes_ingress_self" {
  description       = "Allow unrestricted node-to-node communication within the node security group."
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.nodes.id
}

# Ingress: control plane → kubelet API (health probes, exec, log streaming)
resource "aws_security_group_rule" "nodes_ingress_cluster_kubelet" {
  description              = "Allow the EKS control plane to reach the kubelet API on worker nodes."
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.nodes.id
}

# Ingress: control plane → ephemeral ports (kubectl exec / port-forward return path)
resource "aws_security_group_rule" "nodes_ingress_cluster_ephemeral" {
  description              = "Allow the EKS control plane to use ephemeral ports for exec, logs, and port-forward."
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster.id
  security_group_id        = aws_security_group.nodes.id
}

# Egress: nodes → anywhere (ECR, S3, AWS APIs, internet via NAT Gateway)
resource "aws_security_group_rule" "nodes_egress_all" {
  description       = "Allow all outbound traffic from worker nodes."
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nodes.id
}

# EKS Cluster (Control Plane)

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  tags = merge(var.tags, {
    Name = var.name
  })

  # The cluster role and its policy attachment must exist before the cluster
  # can be created; Terraform cannot infer this from resource references alone.
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# OIDC Identity Provider
#
# Required for IAM Roles for Service Accounts (IRSA). Without this resource,
# no workload running in the cluster can assume an AWS IAM role, which blocks
# the AWS Load Balancer Controller, Cluster Autoscaler, external-dns, etc.

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer

  tags = merge(var.tags, {
    Name = "${var.name}-oidc"
  })
}

# EKS Managed Node Group
#
# Nodes are placed in the private subnets passed via var.subnet_ids.
# scaling_config[0].desired_size is intentionally ignored after initial
# creation so the Cluster Autoscaler can manage the count without Terraform
# fighting it on every subsequent plan.

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = local.node_group_name
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = var.subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size
  labels         = var.node_labels

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = var.node_max_unavailable
  }

  tags = merge(var.tags, {
    Name = local.node_group_name
  })

  # All three node IAM policy attachments must be ready before nodes can
  # register with the cluster — pass the whole for_each map as the dependency.
  depends_on = [aws_iam_role_policy_attachment.nodes]

  lifecycle {
    # Prevent Terraform from reverting desired_size changes made by the
    # Cluster Autoscaler or manual scaling between applies.
    ignore_changes = [scaling_config[0].desired_size]
  }
}
