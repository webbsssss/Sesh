param(
    [string]$ClusterName = "platform-local",
    [string]$RegistryName = "kind-registry"
)

$confirm = Read-Host "This will DESTROY the local kind cluster and registry. Type 'yes' to confirm"
if ($confirm -ne "yes") {
    Write-Host "Aborting." -ForegroundColor Yellow
    exit 0
}

Write-Host "Deleting kind cluster..." -ForegroundColor Green
kind delete cluster --name $ClusterName 2>$null

$container = docker ps -a --filter "name=$RegistryName" --format "{{.Names}}"
if ($container) {
    Write-Host "Removing local registry container..." -ForegroundColor Green
    docker stop $RegistryName 2>$null
    docker rm $RegistryName 2>$null
}

Write-Host "Cleanup complete." -ForegroundColor Green
