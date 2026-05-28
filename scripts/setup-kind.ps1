# kind setup script
param(
    [string]$ClusterName = "platform-local",
    [string]$RegistryName = "kind-registry",
    [int]$RegistryPort = 5001
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Write-Info { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-ErrorColored { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

$required = @("kind", "kubectl", "docker", "helm", "istioctl")
foreach ($cmd in $required) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-ErrorColored "$cmd is required but not found in PATH."
        exit 1
    }
}

Write-Info "Creating kind cluster: $ClusterName"
$existingClusters = cmd /c "kind get clusters 2>nul"
if ($existingClusters -and $existingClusters -match $ClusterName) {
    Write-Warn "Cluster '$ClusterName' already exists. Skipping creation."
} else {
    kind create cluster --config="$ProjectRoot\kind\kind-config.yaml" --name="$ClusterName"
}

$registryRunning = cmd /c "docker inspect -f '{{.State.Running}}' kind-registry 2>nul"
if ($registryRunning -eq "true") {
    Write-Warn "Registry '$RegistryName' already running."
} else {
    $containerExists = cmd /c "docker ps -a --filter name=^kind-registry$ --format {{.Names}} 2>nul"
    if ($containerExists) {
        Write-Warn "Registry container exists but is stopped. Removing old container..."
        cmd /c "docker rm -f kind-registry 2>nul"
    }
    Write-Info "Creating local container registry on port $RegistryPort"
    docker run -d --restart=always -p "127.0.0.1:${RegistryPort}:5000" --name $RegistryName registry:2
}

# Connect registry to kind network (kind creates this network on cluster creation)
$networkExists = docker network ls --filter name=kind --format "{{.Name}}" 2>$null
if ($networkExists -match "kind") {
    $connected = docker network inspect kind --format "{{json .Containers}}" 2>$null | Select-String $RegistryName
    if (-not $connected) {
        docker network connect kind $RegistryName 2>$null
    }
} else {
    Write-Warn "Docker network 'kind' not found. Skipping registry network connect."
}

# Document the registry
@"
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${RegistryPort}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
"@ | kubectl apply -f -

Write-Info "Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=component=controller --timeout=120s

# Configure MetalLB IP pool from Docker kind network (IPv4 only)
$net = cmd /c "docker network inspect kind -f '{{(index .IPAM.Config 0).Subnet}}' 2>nul"
if ($net -match '^\d+\.\d+\.\d+\.\d+') {
    $base = $net.Split('/')[0]
    $prefix = ($base -split '\.') | Select-Object -First 3
    $startIp = "$($prefix -join '.').200"
    $endIp   = "$($prefix -join '.').250"
} else {
    # Docker Desktop may use IPv6; fallback to common Docker IPv4 range
    Write-Warn "Kind network has no IPv4 range detected. Using fallback 172.18.0.200-250."
    $startIp = "172.18.0.200"
    $endIp   = "172.18.0.250"
}

@"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
    - ${startIp}-${endIp}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2adv
  namespace: metallb-system
spec:
  ipAddressPools:
    - kind-pool
"@ | kubectl apply -f -

Write-Info "Installing Istio..."
istioctl install --set profile=default -y
kubectl label namespace default istio-injection=enabled --overwrite

Write-Info "Creating namespaces..."
foreach ($ns in @("payments", "argocd", "argo-rollouts")) {
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
}
kubectl label namespace payments istio-injection=enabled --overwrite

Write-Info "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
Write-Info "Waiting for ArgoCD server..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=180s

Write-Info "Installing Argo Rollouts..."
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

Write-Info "Building payments-api Docker image..."
$imageTag = "localhost:${RegistryPort}/payments-api:v1.0.0"
Push-Location "$ProjectRoot\apps\payments-api"
docker build -t $imageTag -f Dockerfile .
if ($LASTEXITCODE -ne 0) {
    Write-ErrorColored "Docker build failed. Exiting."
    Pop-Location
    exit 1
}
docker push $imageTag
if ($LASTEXITCODE -ne 0) {
    Write-ErrorColored "Docker push failed. Exiting."
    Pop-Location
    exit 1
}
Pop-Location

# Load into kind nodes (fallback if registry push isn't picked up)
cmd /c "kind load docker-image $imageTag --name $ClusterName 2>nul"

Write-Info "Applying Kubernetes manifests..."

# Istio
kubectl apply -f "$ProjectRoot\istio\authz\strict-mtls.yaml"
kubectl apply -f "$ProjectRoot\istio\destination-rules\payments-dr.yaml"
kubectl apply -f "$ProjectRoot\istio\gateways\payments-gateway.yaml"
kubectl apply -f "$ProjectRoot\istio\virtual-services\payments-vs.yaml"

# Argo Rollouts
kubectl apply -f "$ProjectRoot\helm-charts\argo-rollouts\services.yaml"
kubectl apply -f "$ProjectRoot\helm-charts\argo-rollouts\analysis-template.yaml"
kubectl apply -f "$ProjectRoot\helm-charts\argo-rollouts\rollout.yaml"

# ArgoCD Application
kubectl apply -f "$ProjectRoot\helm-charts\argocd-bootstrap\argocd-application.yaml"

# Update rollout image via stdin (kubectl patch JSON is unreliable in PS 5.1)
$rolloutYaml = Get-Content "$ProjectRoot\helm-charts\argo-rollouts\rollout.yaml" -Raw
$rolloutYaml = $rolloutYaml -replace "123456789012.dkr.ecr.us-east-1.amazonaws.com/payments-api:v1.0.0", $imageTag
$rolloutYaml | kubectl apply -f - 2>$null

Write-Info "Setup complete!"
Write-Info ""
Write-Info "Access ArgoCD UI:"
Write-Info "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
Write-Info "  Username: admin"
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>$null
if ($b64) {
    $bytes = [System.Convert]::FromBase64String($b64)
    $pw = [System.Text.Encoding]::UTF8.GetString($bytes)
} else {
    $pw = "(fetch manually: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
}
Write-Info "  Password: $pw"
Write-Info ""
Write-Info "Test payments API:"
Write-Info "  kubectl port-forward svc/payments-api -n payments 8083:8080"
Write-Info "  curl http://localhost:8083/health"
Write-Info ""
Write-Info "Run demos:"
Write-Info "  .\scripts\demo-self-healing.ps1"
Write-Info "  .\scripts\demo-canary.ps1"
