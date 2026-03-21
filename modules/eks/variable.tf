# General

variable "name" {
  description = "Name of the EKS cluster. Used as a prefix for all associated resources."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 100
    error_message = "Cluster name must be between 1 and 100 characters."
  }
}

variable "tags" {
  description = "Map of additional tags to merge into every resource created by this module."
  type        = map(string)
  default     = {}
}

# Cluster (Control Plane)
variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane (e.g. \"1.30\"). AWS supports the three most recent minor versions."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID of the VPC in which the EKS cluster and worker nodes will be created."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs used for both control-plane ENI placement and the managed node group. Subnets must span at least two AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets in different AZs are required for an EKS cluster."
  }
}

variable "cluster_endpoint_private_access" {
  description = "Whether the Amazon EKS private API server endpoint is enabled. When true, Kubernetes API requests from within the VPC use the private endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled. When false, only private endpoint access is allowed."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to reach the public API server endpoint. Only effective when cluster_endpoint_public_access is true. Restrict this in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.cluster_endpoint_public_access_cidrs : can(cidrnetmask(c))])
    error_message = "All entries in cluster_endpoint_public_access_cidrs must be valid CIDR blocks."
  }
}

variable "enabled_cluster_log_types" {
  description = "List of EKS control-plane log types to send to CloudWatch. Valid values: api, audit, authenticator, controllerManager, scheduler."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for t in var.enabled_cluster_log_types :
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], t)
    ])
    error_message = "Valid log types are: api, audit, authenticator, controllerManager, scheduler."
  }
}

# Managed Node Group
variable "node_group_name" {
  description = "Explicit name for the managed node group. Defaults to \"<name>-nodes\" when null."
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "List of EC2 instance types for the managed node group. EKS uses the first type that satisfies capacity constraints."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for the managed node group. ON_DEMAND provides reliability; SPOT reduces cost by up to 90% with possible interruption."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be either ON_DEMAND or SPOT."
  }
}

variable "node_disk_size" {
  description = "Root EBS volume size (GiB) for each worker node. Minimum recommended is 20 GiB."
  type        = number
  default     = 20

  validation {
    condition     = var.node_disk_size >= 20
    error_message = "node_disk_size must be at least 20 GiB."
  }
}

variable "node_desired_size" {
  description = "Desired number of worker nodes. Ignored by Terraform after initial creation when managed by the Cluster Autoscaler (see lifecycle ignore_changes)."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes the autoscaler may scale down to."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes the autoscaler may scale up to."
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= var.node_min_size
    error_message = "node_max_size must be greater than or equal to node_min_size."
  }
}

variable "node_max_unavailable" {
  description = "Maximum number of nodes that can be unavailable simultaneously during a node group update. Must be at least 1."
  type        = number
  default     = 1

  validation {
    condition     = var.node_max_unavailable >= 1
    error_message = "node_max_unavailable must be at least 1."
  }
}

variable "node_labels" {
  description = "Map of Kubernetes labels to apply to all nodes in the managed node group."
  type        = map(string)
  default     = {}
}
