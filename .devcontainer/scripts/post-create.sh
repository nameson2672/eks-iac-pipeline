#!/bin/bash
set -e

echo "==> Architecture: $(uname -m)"
echo ""

echo "==> Verifying tools..."
terraform -version
aws --version
kubectl version --client --short 2>/dev/null || kubectl version --client
helm version --short
eksctl version

echo ""
echo "==> Configuring git..."
git config --global core.autocrlf input
git config --global init.defaultBranch main

# Run terraform init if directory exists
if [ -d "terraform" ]; then
  echo ""
  echo "==> Running terraform init..."
  cd terraform && terraform init -upgrade && cd ..
fi

echo ""
echo "==> Dev container ready!"
