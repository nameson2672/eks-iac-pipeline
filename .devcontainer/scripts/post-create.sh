#!/bin/bash
set -e

echo "==> Verifying tools..."
terraform -version
aws --version
kubectl version --client --short
helm version --short
eksctl version 2>/dev/null || echo "eksctl not installed (optional)"

# Install tflint (optional but useful)
curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# Terraform init if directory exists
if [ -d "terraform" ]; then
  echo "==> Running terraform init..."
  cd terraform && terraform init -upgrade
  cd ..
fi

echo "==> Dev container ready!"
