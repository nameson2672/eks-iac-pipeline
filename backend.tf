terraform {
  backend "s3" {
    bucket         = "eks-iac-tf-state"
    key            = "eks/terraform.tfstate"
    region         = "ca-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
