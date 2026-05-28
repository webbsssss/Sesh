#!/usr/bin/env bash
set -euo pipefail

KIND_CLUSTER_NAME="platform-local"
REGISTRY_NAME="kind-registry"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${RED}[WARN]${NC} $*"; }

log_warn "This will DESTROY the local kind cluster and registry. Are you sure? (yes/no)"
read -r confirm
if [[ "$confirm" != "yes" ]]; then
  log_info "Aborting."
  exit 0
fi

log_info "Deleting kind cluster..."
kind delete cluster --name "$KIND_CLUSTER_NAME" || true

if docker inspect "$REGISTRY_NAME" &>/dev/null; then
  log_info "Removing local registry container..."
  docker stop "$REGISTRY_NAME" &>/dev/null || true
  docker rm "$REGISTRY_NAME" &>/dev/null || true
fi

log_info "Cleanup complete."
