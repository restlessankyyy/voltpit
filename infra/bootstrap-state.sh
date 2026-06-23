#!/usr/bin/env bash
# Bootstrap the Azure Storage Account that holds Terraform remote state.
#
# Run this ONCE per subscription before `terraform init`. It is idempotent:
# re-running it is safe and just re-confirms the resources and backend.hcl.
#
# Why a separate script (not Terraform)? The backend storage must exist before
# Terraform can initialise its backend, so it cannot manage its own state. This
# is the standard "bootstrap" pattern for the azurerm backend.
set -euo pipefail

cd "$(dirname "$0")"

# ── Config (override via env vars if you like) ───────────────────────────────
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
LOCATION="${LOCATION:-swedencentral}"
STATE_RG="${STATE_RG:-tesladash-tfstate-rg}"
CONTAINER="${CONTAINER:-tfstate}"
STATE_KEY="${STATE_KEY:-tesladash.tfstate}"

# Storage account names are globally unique, 3-24 lowercase alphanumerics.
# Derive a deterministic, idempotent name from the subscription ID so repeat
# runs target the same account without storing extra state.
if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
  if command -v md5sum >/dev/null 2>&1; then
    HASH="$(printf '%s' "$SUBSCRIPTION_ID" | md5sum | cut -c1-8)"
  else
    HASH="$(printf '%s' "$SUBSCRIPTION_ID" | md5 | cut -c1-8)"
  fi
  STORAGE_ACCOUNT="tesladashtf${HASH}"
fi

echo "==> Using:"
echo "    subscription:    $SUBSCRIPTION_ID"
echo "    location:        $LOCATION"
echo "    resource group:  $STATE_RG"
echo "    storage account: $STORAGE_ACCOUNT"
echo "    container:       $CONTAINER"
echo "    state key:       $STATE_KEY"
echo

az account set --subscription "$SUBSCRIPTION_ID"

echo "==> Resource group"
az group create \
  --name "$STATE_RG" \
  --location "$LOCATION" \
  --tags purpose=terraform-state app=tesladash \
  --only-show-errors --output none

echo "==> Storage account (versioning + soft delete for state safety)"
if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$STATE_RG" \
  --only-show-errors >/dev/null 2>&1; then
  az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$STATE_RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    --tags purpose=terraform-state app=tesladash \
    --only-show-errors --output none
fi

# Blob versioning + soft delete protect state against accidental corruption.
az storage account blob-service-properties update \
  --account-name "$STORAGE_ACCOUNT" \
  --resource-group "$STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  --only-show-errors --output none

echo "==> Grant the signed-in user data-plane access (Storage Blob Data Contributor)"
USER_OID="$(az ad signed-in-user show --query id -o tsv)"
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${STATE_RG}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
az role assignment create \
  --assignee-object-id "$USER_OID" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "$SCOPE" \
  --only-show-errors --output none 2>/dev/null || true

echo "==> Create state container (Azure AD auth)"
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login \
  --only-show-errors --output none

echo "==> Write backend.hcl"
cat > backend.hcl <<EOF
resource_group_name  = "${STATE_RG}"
storage_account_name = "${STORAGE_ACCOUNT}"
container_name       = "${CONTAINER}"
key                  = "${STATE_KEY}"
EOF

echo
echo "Done. Initialise (or migrate existing local state) with:"
echo "    terraform init -backend-config=backend.hcl"
echo
echo "If you have existing local state to move into the backend, run:"
echo "    terraform init -migrate-state -backend-config=backend.hcl"
