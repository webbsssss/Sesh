# Incident Response Runbook

## Symptom: Payments API returning 5xx errors

### 1. Check pod health
```bash
kubectl get pods -n payments -l app.kubernetes.io/name=payments-api
kubectl describe pod <pod-name> -n payments
kubectl logs -n payments -l app.kubernetes.io/name=payments-api --tail=100
```

### 2. Check rollout status
```bash
kubectl get rollout payments-api -n payments
kubectl describe rollout payments-api -n payments
```

### 3. Check Istio sidecar logs
```bash
kubectl logs -n payments -l app.kubernetes.io/name=payments-api -c istio-proxy --tail=100
```

### 4. Check destination rule / virtual service
```bash
istioctl analyze -n payments
kubectl get vs,dr -n payments -o yaml
```

### 5. Rollback if needed
```bash
# Abort canary and revert to stable image
kubectl patch rollout payments-api -n payments --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "localhost:5001/payments-api:v1.0.0"}]'
```

## Symptom: ArgoCD out of sync

### 1. Check application status
```bash
argocd app get payments-api
```

### 2. Force sync
```bash
argocd app sync payments-api --force
```

### 3. Check for manual drift
```bash
argocd app diff payments-api
```

## Symptom: Node unresponsive / pods stuck pending

### 1. Check node status
```bash
kubectl get nodes -o wide
kubectl describe node <node-name>
```

### 2. Check cluster autoscaler logs
```bash
kubectl logs -n kube-system -l app=cluster-autoscaler
```

### 3. Cordon and drain if needed
```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```
