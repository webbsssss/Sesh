# Architecture

## Overview

```
  Users
    |
    v
  Istio Ingress Gateway (443)
    |
    v
  VirtualService (90% stable / 10% canary)
    |
    +----> Stable Subset (v1)
    |
    +----> Canary Subset (v2)
    |
  DestinationRule (mTLS + Outlier Detection)
    |
    v
  Payments API Pods (Argo Rollout)
```

## Component Breakdown

| Component | Purpose |
|-----------|---------|
| **EKS** | Managed Kubernetes control plane |
| **Istio** | Service mesh with mTLS, traffic splitting, retries, timeouts |
| **ArgoCD** | GitOps controller that ensures cluster state matches Git |
| **Argo Rollouts** | Progressive delivery with automated canary analysis |
| **Helm** | Packaging and templating Kubernetes manifests |
| **Terraform** | Infrastructure provisioning (EKS, VPC, IAM) |

## Security Model

- **PeerAuthentication STRICT** — All inter-pod traffic is encrypted with mTLS.
- **AuthorizationPolicy** — Explicit allow-list for HTTP methods and paths.
- **SecurityContext** — Non-root, read-only root filesystem, dropped capabilities.
- **KMS Envelope Encryption** — Kubernetes Secrets encrypted at rest.

## Self-Healing Mechanisms

1. **Pod Failure** — Deployment/Rollout controller creates replacement pod.
2. **Node Failure** — Kubernetes scheduler reschedules pods to healthy nodes.
3. **Drift** — ArgoCD auto-syncs cluster state back to Git within minutes.
4. **Canary Failure** — Argo Rollouts aborts promotion if success-rate analysis fails.
