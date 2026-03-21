env          = "dev"
aws_region   = "ca-central-1"
project_name = "eks-iac-pipeline"

tf_state_bucket     = "eks-iac-tf-state"
tf_state_lock_table = "terraform-state-lock"

aws_subnet-1          = "ca-central-1a"
aws_subnet-2          = "ca-central-1b"
public_subnet_cidr_1  = "10.0.1.0/24"
public_subnet_cidr_2  = "10.0.2.0/24"
private_subnet_cidr_1 = "10.0.10.0/24"
private_subnet_cidr_2 = "10.0.11.0/24"

enable_nat_gateway      = true
map_public_ip_on_launch = false
