#!/usr/bin/env bash
set -uo pipefail

# Demo: Self-healing via ArgoCD + Kubernetes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[DEMO]${NC} $*"; }

POD_NAME=$(kubectl get pods -n payments -l app.kubernetes.io/name=payments-api -o jsonpath='{.items[0].metadata.name}')
NODE_NAME=$(kubectl get pod "$POD_NAME" -n payments -o jsonpath='{.spec.nodeName}')

log_info "Current pod: $POD_NAME on node: $NODE_NAME"
log_warn "Deleting pod $POD_NAME..."
kubectl delete pod "$POD_NAME" -n payments --wait=false

log_info "Watching for replacement pod..."
sleep 2
kubectl get pods -n payments -l app.kubernetes.io/name=payments-api -w &
WATCH_PID=$!
sleep 10
kill "$WATCH_PID" 2>/dev/null || true

NEW_POD=$(kubectl get pods -n payments -l app.kubernetes.io/name=payments-api -o jsonpath='{.items[0].metadata.name}')
log_info "New pod created: $NEW_POD"

log_warn "Simulating node failure: cordoning node $NODE_NAME"
kubectl cordon "$NODE_NAME"
kubectl delete pod "$NEW_POD" -n payments --wait=false

sleep 12
kubectl get pods -n payments -l app.kubernetes.io/name=payments-api
kubectl uncordon "$NODE_NAME" 2>/dev/null || true

log_info "Self-healing demo complete."
