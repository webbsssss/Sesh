# Canary deployment demo (no kubectl-argo-rollouts plugin required)

Write-Host "Current rollout status:" -ForegroundColor Cyan
kubectl get rollout payments-api -n payments

Write-Host "`nCurrent pods:" -ForegroundColor Cyan
kubectl get pods -n payments -l app.kubernetes.io/name=payments-api

Write-Host "`nRe-tagging image as v2.0.0 to trigger canary..." -ForegroundColor Yellow
$imageV1 = "localhost:5001/payments-api:v1.0.0"
$imageV2 = "localhost:5001/payments-api:v2.0.0"
docker tag $imageV1 $imageV2
docker push $imageV2

Write-Host "`nLoading v2.0.0 image into kind nodes..." -ForegroundColor Yellow
kind load docker-image $imageV2 --name platform-local

Write-Host "`nPatching rollout to use v2.0.0..." -ForegroundColor Yellow
$rolloutYaml = kubectl get rollout payments-api -n payments -o yaml
$rolloutYaml = $rolloutYaml -replace [regex]::Escape($imageV1), $imageV2
$rolloutYaml | kubectl apply -f -

Write-Host "`nWatching rollout progress (10 checks, 10s intervals)..." -ForegroundColor Green
for ($i = 1; $i -le 10; $i++) {
    Start-Sleep -Seconds 10
    Write-Host "`nCheck $i"
    kubectl get rollout payments-api -n payments
    kubectl get pods -n payments -l app.kubernetes.io/name=payments-api
}

Write-Host "`nCanary demo complete." -ForegroundColor Green
