# Self-healing demo: delete a pod and watch it respawn

$pod = kubectl get pods -n payments -l app.kubernetes.io/name=payments-api -o jsonpath='{.items[0].metadata.name}'
$node = kubectl get pod $pod -n payments -o jsonpath='{.spec.nodeName}'

Write-Host "Current pod: $pod on node: $node" -ForegroundColor Cyan
Write-Host "Deleting pod $pod..." -ForegroundColor Yellow
kubectl delete pod $pod -n payments --wait=$false

Write-Host "Watching for replacement pod..." -ForegroundColor Green
Start-Sleep -Seconds 2

# Poll for new pod instead of background watch (PS 5.1 compatible)
$attempts = 0
$newPod = $pod
while ($newPod -eq $pod -and $attempts -lt 20) {
    Start-Sleep -Seconds 2
    $newPod = kubectl get pods -n payments -l app.kubernetes.io/name=payments-api -o jsonpath='{.items[0].metadata.name}' 2>$null
    $attempts++
}

Write-Host "New pod created: $newPod" -ForegroundColor Green

Write-Host "Simulating node failure: cordoning node $node" -ForegroundColor Yellow
kubectl cordon $node
kubectl delete pod $newPod -n payments --wait=$false

Start-Sleep -Seconds 12
kubectl get pods -n payments -l app.kubernetes.io/name=payments-api
kubectl uncordon $node 2>$null

Write-Host "Self-healing demo complete." -ForegroundColor Green
