#!/usr/bin/env bash
# Deploy the Tesla Dash backend to Azure Container Apps with Terraform.
# Builds the image in the cloud (az acr build), so no local Docker is needed.
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f terraform.tfvars ]]; then
  echo "terraform.tfvars not found. Creating it from the example..."
  cp terraform.tfvars.example terraform.tfvars
  echo "Edit infra/terraform.tfvars if needed, then re-run ./deploy.sh"
fi

echo "==> az login check"
az account show >/dev/null 2>&1 || az login

if [[ ! -f backend.hcl ]]; then
  echo "==> Bootstrapping Terraform remote state storage"
  ./bootstrap-state.sh
fi

echo "==> terraform init (remote state in Azure Storage)"
terraform init -input=false -backend-config=backend.hcl

echo "==> terraform apply"
terraform apply -auto-approve

echo
echo "Done. Stream URL for the iOS app:"
terraform output -raw stream_url
echo
