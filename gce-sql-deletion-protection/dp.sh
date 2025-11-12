#!/bin/bash
# --------------------------------------------------------------------
# Script: enable-deletion-protection.sh
# Purpose: Enable deletion protection for all Compute Engine VMs and
#          Cloud SQL instances in the specified GCP project.
# Author: Bharath Sampath
# --------------------------------------------------------------------

# Exit on error
set -euo pipefail

# ---- Configuration ----
PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ ERROR: No project ID provided or configured."
  echo "Usage: $0 <PROJECT_ID>"
  exit 1
fi

echo "🔹 Enabling deletion protection for all resources in project: $PROJECT_ID"

# ---- Enable for Compute Engine VMs ----
echo "🖥️  Checking Compute Engine instances..."
VM_LIST=$(gcloud compute instances list --project="$PROJECT_ID" --format="value(name,zone)")

if [[ -z "$VM_LIST" ]]; then
  echo "✅ No Compute Engine instances found."
else
  echo "$VM_LIST" | while read -r VM_NAME ZONE; do
    echo "➡️  Enabling deletion protection for VM: $VM_NAME in zone: $ZONE"
    gcloud compute instances update "$VM_NAME" \
      --zone="$ZONE" \
      --deletion-protection \
      --project="$PROJECT_ID" >/dev/null
  done
  echo "✅ Deletion protection enabled for all VMs."
fi

# ---- Enable for Cloud SQL Instances ----
echo "🗄️  Checking Cloud SQL instances..."
SQL_INSTANCES=$(gcloud sql instances list --project="$PROJECT_ID" --format="value(name)")

if [[ -z "$SQL_INSTANCES" ]]; then
  echo "✅ No Cloud SQL instances found."
else
  echo "$SQL_INSTANCES" | while read -r SQL_INSTANCE; do
    echo "➡️  Enabling deletion protection for Cloud SQL instance: $SQL_INSTANCE"
    gcloud sql instances patch "$SQL_INSTANCE" \
      --deletion-protection \
      --project="$PROJECT_ID" >/dev/null
  done
  echo "✅ Deletion protection enabled for all Cloud SQL instances."
fi

echo "🎉 All resources now have deletion protection enabled in project: $PROJECT_ID"
