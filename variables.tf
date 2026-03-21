variable "project_name" {}
variable "aws_region" {}
variable "env" {}

variable "tf_state_bucket" {}
variable "tf_state_lock_table" {}

variable "aws_subnet-1" {}
variable "aws_subnet-2" {}
variable "public_subnet_cidr_1" {}
variable "public_subnet_cidr_2" {}
variable "private_subnet_cidr_1" {}
variable "private_subnet_cidr_2" {}
variable "enable_nat_gateway" {}
variable "map_public_ip_on_launch" {}
