# Local Setup Guide (kind + Docker Desktop)

Run everything on your laptop for free.

## Prerequisites

- **Docker Desktop** (Windows/Mac/Linux) or Docker Engine + systemd (Linux)
- **kind** — [installation guide](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- **kubectl** — [installation guide](https://kubernetes.io/docs/tasks/tools/)
- **istioctl** — `curl -L https://istio.io/downloadIstio | sh -`
- **helm** — [installation guide](https://helm.sh/docs/intro/install/)
- **bash** — Git Bash, WSL, or macOS/Linux terminal


## Quick Start

1. **Setup** (from repo root in bash):

```bash
chmod +x scripts/setup-kind.sh scripts/teardown-kind.sh
./scripts/setup-kind.sh
```

This script does everything:
- Creates a 3-node kind cluster
- Starts a local container registry on port `5001`
- Installs MetalLB for LoadBalancer services
- Installs Istio with sidecar injection
- Installs ArgoCD + Argo Rollouts
- Builds and loads the payments-api Docker image
- Applies all Istio, Rollout, and ArgoCD manifests

2. **Access ArgoCD UI**

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open `https://localhost:8080` in your browser.

- Username: `admin`
- Password: run `make argocd-password`

3. **Test the payments API**

```bash
# Port-forward to the service directly
kubectl port-forward svc/payments-api -n payments 8083:8080

# In another terminal
curl http://localhost:8083/health
curl http://localhost:8083/ready
curl http://localhost:8083/version
curl -X POST http://localhost:8083/payment
```

4. **Run the demos**

```bash
# Self-healing: delete a pod, watch it respawn
make demo-self-healing

# Canary: promote rollout and watch traffic shift
make demo-canary
```

## Architecture (Local)

```
┌─────────────────────────────────────────────┐
│               Docker Desktop                 │
│  ┌───────────────────────────────────────┐    │
│  │      kind cluster (3 nodes)         │    │
│  │  ┌─────────┐  ┌──────┐  ┌──────┐   │    │
│  │  │ Control │  │Worker│  │Worker│   │    │
│  │  │ Plane   │  │Node 1│  │Node 2│   │    │
│  │  └────┬────┘  └──┬───┘  └──┬───┘   │    │
│  │       │          │         │       │    │
│  │  ┌────┴──────────────────────────┐  │    │
│  │  │  Istio Ingress Gateway        │  │    │
│  │  │  (port-forward or MetalLB IP) │  │    │
│  │  └────┬──────────────────────────┘  │    │
│  │       │                             │    │
│  │  ┌────┴──────────────────────────┐  │    │
│  │  │  VirtualService 90/10 split   │  │    │
│  │  │  → stable (v1) / canary (v2)  │  │    │
│  │  └────┬────────────────────┬────┘  │    │
│  │       │                    │       │    │
│  │  ┌────┴────┐          ┌────┴────┐ │    │
│  │  │ stable  │          │ canary  │ │    │
│  │  │ pods    │          │ pods    │ │    │
│  │  └─────────┘          └─────────┘ │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Cleanup

```bash
./scripts/teardown-kind.sh
```

## Troubleshooting

### Pods stuck in Pending

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Check if kind cluster is healthy:
```bash
kind get clusters
kubectl get nodes
```

### Image pull errors (ErrImagePull)

The local registry runs on `localhost:5001`. If pods can't pull images:

```bash
# Option 1: Load image directly into kind nodes
kind load docker-image localhost:5001/payments-api:v1.0.0 --name platform-local

# Option 2: Use Docker Hub / GHCR public image
# Edit helm-charts/argo-rollouts/rollout.yaml and helm-charts/microservice/values.yaml
```

### MetalLB not assigning IPs

```bash
kubectl get ipaddresspools -n metallb-system
kubectl get l2advertisements -n metallb-system
kubectl logs -n metallb-system -l component=speaker
```

### Istio sidecar not injected

```bash
kubectl get namespace payments -o jsonpath='{.metadata.labels.istio-injection}'
# Should be "enabled"
kubectl label namespace payments istio-injection=enabled --overwrite
kubectl rollout restart deployment payments-api -n payments
```

## Cost

**$0** — everything runs inside Docker containers on your local machine.
