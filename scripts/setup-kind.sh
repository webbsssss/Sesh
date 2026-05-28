#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KIND_CLUSTER_NAME="platform-local"
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

for cmd in kind kubectl docker helm istioctl; do
  if ! command -v "$cmd" &>/dev/null; then
    log_error "$cmd is required but not installed."
    exit 1
  fi
done

log_info "Creating kind cluster: $KIND_CLUSTER_NAME"
kind create cluster --config="${PROJECT_ROOT}/kind/kind-config.yaml" --name="$KIND_CLUSTER_NAME" || {
  log_warn "Cluster already exists or failed to create. Continuing..."
}

if [ "$(docker inspect -f '{{.State.Running}}' "$REGISTRY_NAME" 2>/dev/null || true)" != "true" ]; then
  log_info "Creating local container registry: $REGISTRY_NAME:$REGISTRY_PORT"
  docker run -d --restart=always -p "127.0.0.1:$REGISTRY_PORT:5000" --name "$REGISTRY_NAME" registry:2 || true
fi

if ! docker network inspect kind | grep -q "$REGISTRY_NAME"; then
  docker network connect kind "$REGISTRY_NAME" 2>/dev/null || true
fi

kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${REGISTRY_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

log_info "Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml

kubectl wait --namespace metallb-system --for=condition=ready pod --selector=component=controller --timeout=120s

KIND_NET_CIDR=$(docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}')
KIND_NET_BASE=$(echo "$KIND_NET_CIDR" | awk -F/ '{print $1}')
NET_PREFIX=$(echo "$KIND_NET_BASE" | awk -F. '{printf "%s.%s.%s", $1, $2, $3}')
START_IP="${NET_PREFIX}.200"
END_IP="${NET_PREFIX}.250"

kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - ${START_IP}-${END_IP}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
EOF

log_info "Installing Istio..."
istioctl install --set profile=default -y
kubectl label namespace default istio-injection=enabled --overwrite

log_info "Creating namespaces..."
kubectl create namespace payments --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace payments istio-injection=enabled --overwrite

log_info "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

log_info "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s || true

log_info "Installing Argo Rollouts..."
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

log_info "Building payments-api Docker image..."
cd "${PROJECT_ROOT}/apps/payments-api"
docker build -t "localhost:${REGISTRY_PORT}/payments-api:v1.0.0" -f Dockerfile .
docker push "localhost:${REGISTRY_PORT}/payments-api:v1.0.0"

kind load docker-image "localhost:${REGISTRY_PORT}/payments-api:v1.0.0" --name "$KIND_CLUSTER_NAME" 2>/dev/null || true

log_info "Applying Kubernetes manifests..."

kubectl apply -f "${PROJECT_ROOT}/istio/authz/strict-mtls.yaml"
kubectl apply -f "${PROJECT_ROOT}/istio/destination-rules/payments-dr.yaml"
kubectl apply -f "${PROJECT_ROOT}/istio/gateways/payments-gateway.yaml"
kubectl apply -f "${PROJECT_ROOT}/istio/virtual-services/payments-vs.yaml"

kubectl apply -f "${PROJECT_ROOT}/helm-charts/argo-rollouts/services.yaml"
kubectl apply -f "${PROJECT_ROOT}/helm-charts/argo-rollouts/analysis-template.yaml"
kubectl apply -f "${PROJECT_ROOT}/helm-charts/argo-rollouts/rollout.yaml"

kubectl apply -f "${PROJECT_ROOT}/helm-charts/argocd-bootstrap/argocd-application.yaml"

kubectl set image rollout/payments-api -n payments payments-api="localhost:${REGISTRY_PORT}/payments-api:v1.0.0" || true

log_info "Setup complete!"
log_info ""
log_info "Access ArgoCD UI:"
log_info "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
log_info "  Username: admin"
PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
log_info "  Password: ${PASS:-(fetch with kubectl)}"
log_info ""
log_info "Access Istio Ingress Gateway (via MetalLB):"
log_info "  kubectl get svc istio-ingressgateway -n istio-system"
log_info "  Or via port-forward: kubectl port-forward svc/istio-ingressgateway -n istio-system 8082:80"
log_info ""
log_info "Test payments API:"
log_info "  kubectl port-forward svc/payments-api -n payments 8083:8080"
log_info "  curl http://localhost:8083/health"
