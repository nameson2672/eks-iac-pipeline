module "eks" {
  source = "./modules/eks"

  project_name = var.project_name
  env         = var.env

}
