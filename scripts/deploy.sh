#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
    echo "Usage: $0 [--env dev|prod] [--skip-infra] [--skip-apps]"
    exit 1
}

ENV="dev"
SKIP_INFRA=false
SKIP_APPS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env) ENV="$2"; shift 2 ;;
        --skip-infra) SKIP_INFRA=true; shift ;;
        --skip-apps) SKIP_APPS=true; shift ;;
        -h|--help) usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

log_info "Deploying Platform Engineering stack | env=$ENV"

# 1. Provision EKS with Terraform
if [[ "$SKIP_INFRA" == false ]]; then
    log_info "Step 1/4: Provisioning EKS cluster via Terraform..."
    cd "${PROJECT_ROOT}/terraform/environments/${ENV}"
    terraform init
    terraform apply -auto-approve
    log_info "EKS cluster ready. Updating kubeconfig..."
    CLUSTER_NAME=$(terraform output -raw cluster_name)
    aws eks update-kubeconfig --region us-east-1 --name "$CLUSTER_NAME"
else
    log_warn "Skipping infrastructure provisioning."
fi

# 2. Install Istio
if [[ "$SKIP_APPS" == false ]]; then
    log_info "Step 2/4: Installing Istio service mesh..."
    if ! command -v istioctl &>/dev/null; then
        log_warn "istioctl not found. Install Istio CLI first:"
        log_warn "  curl -L https://istio.io/downloadIstio | sh -"
        exit 1
    fi
    istioctl install --set profile=default -y
    kubectl label namespace payments istio-injection=enabled --overwrite 2>/dev/null || true

    # 3. Install ArgoCD
    log_info "Step 3/4: Installing ArgoCD..."
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

    # 4. Install Argo Rollouts
    log_info "Step 4/4: Installing Argo Rollouts..."
    kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

    # Apply manifests
    log_info "Applying Istio manifests..."
    kubectl apply -f "${PROJECT_ROOT}/istio/authz/strict-mtls.yaml"
    kubectl apply -f "${PROJECT_ROOT}/istio/destination-rules/payments-dr.yaml"
    kubectl apply -f "${PROJECT_ROOT}/istio/gateways/payments-gateway.yaml"
    kubectl apply -f "${PROJECT_ROOT}/istio/virtual-services/payments-vs.yaml"

    log_info "Applying Argo Rollouts manifests..."
    kubectl apply -f "${PROJECT_ROOT}/helm-charts/argo-rollouts/services.yaml"
    kubectl apply -f "${PROJECT_ROOT}/helm-charts/argo-rollouts/analysis-template.yaml"
    kubectl apply -f "${PROJECT_ROOT}/helm-charts/argo-rollouts/rollout.yaml"

    log_info "Creating ArgoCD application..."
    kubectl apply -f "${PROJECT_ROOT}/helm-charts/argocd-bootstrap/argocd-application.yaml"

    log_info "Deployment complete!"
    log_info "ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
    PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    log_info "ArgoCD admin password: $PASSWORD"
else
    log_warn "Skipping application deployment."
fi

log_info "Done."
