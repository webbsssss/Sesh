#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV="dev"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${RED}[WARN]${NC} $*"; }

log_warn "This will DESTROY the EKS cluster and all workloads. Are you sure? (yes/no)"
read -r confirm
if [[ "$confirm" != "yes" ]]; then
    log_info "Aborting."
    exit 0
fi

log_info "Destroying Terraform-managed infrastructure..."
cd "${PROJECT_ROOT}/terraform/environments/${ENV}"
terraform destroy -auto-approve

log_info "Cleanup complete. Verify in AWS Console that all resources are removed."
