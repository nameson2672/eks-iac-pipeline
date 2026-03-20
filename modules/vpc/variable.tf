variable "name" {
  description = "Name prefix applied to all resources created by this module."
  type        = string

  validation {
    condition     = length(var.name) > 0
    error_message = "The name variable must not be empty."
  }
}

variable "vpc_cidr" {
  description = "The IPv4 CIDR block for the VPC (e.g. \"10.0.0.0/16\")."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "Exactly 2 availability zone names in which to create the public and private subnets (e.g. [\"us-east-1a\", \"us-east-1b\"])."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly 2 availability zones must be provided."
  }
}

variable "public_subnet_cidrs" {
  description = "List of exactly 2 IPv4 CIDR blocks for the public subnets. Must be within var.vpc_cidr and in the same order as var.availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Exactly 2 public subnet CIDRs must be provided."
  }

  validation {
    condition     = alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "All public_subnet_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "List of exactly 2 IPv4 CIDR blocks for the private subnets. Must be within var.vpc_cidr and in the same order as var.availability_zones."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly 2 private subnet CIDRs must be provided."
  }

  validation {
    condition     = alltrue([for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr))])
    error_message = "All private_subnet_cidrs must be valid IPv4 CIDR blocks."
  }
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway (and its associated Elastic IP) in the first public subnet. Set to false to save costs in non-production environments."
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = "Whether instances launched into a public subnet should be assigned a public IPv4 address automatically."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Map of additional tags to apply to every resource created by this module. Merged with a Name tag generated per resource."
  type        = map(string)
  default     = {}
}
