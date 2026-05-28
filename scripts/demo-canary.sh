#!/usr/bin/env bash
set -uo pipefail

# Demo: Canary deployment with Argo Rollouts + Istio
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[DEMO]${NC} $*"; }

log_info "Current rollout status:"
kubectl get rollout payments-api -n payments

log_warn "Re-tagging image as v2.0.0 to trigger canary..."
docker tag localhost:5001/payments-api:v1.0.0 localhost:5001/payments-api:v2.0.0
docker push localhost:5001/payments-api:v2.0.0
kind load docker-image localhost:5001/payments-api:v2.0.0 --name platform-local 2>/dev/null || true

log_warn "Patching rollout to use v2.0.0..."
kubectl patch rollout payments-api -n payments --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "localhost:5001/payments-api:v2.0.0"}]'

log_info "Watching rollout progress (10 checks, 10s intervals)..."
for i in {1..10}; do
    sleep 10
    echo -e "\nCheck $i"
    kubectl get rollout payments-api -n payments
    kubectl get pods -n payments -l app.kubernetes.io/name=payments-api
done

log_info "Canary demo complete."

