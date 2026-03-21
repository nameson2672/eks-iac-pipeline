module "eks" {
  source     = "./modules/eks"
  name       = var.project_name
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids_list

  cluster_version           = "1.30"
  enabled_cluster_log_types = ["api", "audit", "authenticator"]
  tags = {
    Environment = var.env
    Project     = var.project_name
  }
  depends_on = [module.vpc]
}

module "vpc" {
  source = "./modules/vpc"

  name         = var.project_name
  cluster_name = var.project_name
  vpc_cidr     = "10.0.0.0/16"

  availability_zones   = [var.aws_subnet-1, var.aws_subnet-2]
  public_subnet_cidrs  = [var.public_subnet_cidr_1, var.public_subnet_cidr_2]
  private_subnet_cidrs = [var.private_subnet_cidr_1, var.private_subnet_cidr_2]

  enable_nat_gateway      = var.enable_nat_gateway
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags = {
    Environment = var.env
    Project     = var.project_name
  }
}
