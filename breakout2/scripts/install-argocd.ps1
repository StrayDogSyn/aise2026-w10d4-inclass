# ArgoCD Installation Script
# This script automates the installation and initial setup of ArgoCD

Write-Host "================================" -ForegroundColor Cyan
Write-Host "ArgoCD Installation Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify cluster connectivity
Write-Host "[1/6] Verifying cluster connectivity..." -ForegroundColor Yellow
try {
    $clusterInfo = kubectl cluster-info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Cannot connect to Kubernetes cluster" -ForegroundColor Red
        Write-Host "Please ensure your cluster is running and kubectl is configured" -ForegroundColor Red
        Write-Host "Run: gcloud container clusters get-credentials prod-ml-cluster --region us-central1" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✓ Cluster connectivity verified" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to verify cluster connectivity" -ForegroundColor Red
    exit 1
}

# Step 2: Create ArgoCD namespace
Write-Host "[2/6] Creating ArgoCD namespace..." -ForegroundColor Yellow
kubectl create namespace argocd 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ ArgoCD namespace created" -ForegroundColor Green
} else {
    $namespaceExists = kubectl get namespace argocd 2>&1
    if ($namespaceExists -match "argocd") {
        Write-Host "✓ ArgoCD namespace already exists" -ForegroundColor Green
    } else {
        Write-Host "ERROR: Failed to create ArgoCD namespace" -ForegroundColor Red
        exit 1
    }
}

# Step 3: Install ArgoCD
Write-Host "[3/6] Installing ArgoCD components..." -ForegroundColor Yellow
Write-Host "    This may take 2-3 minutes..." -ForegroundColor Gray
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ ArgoCD manifests applied" -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to install ArgoCD" -ForegroundColor Red
    exit 1
}

# Step 4: Wait for ArgoCD pods to be ready
Write-Host "[4/6] Waiting for ArgoCD pods to be ready..." -ForegroundColor Yellow
Write-Host "    This may take 2-3 minutes..." -ForegroundColor Gray
Start-Sleep -Seconds 30  # Give pods time to start initializing

$maxWait = 300  # 5 minutes
$elapsed = 0
$interval = 10

while ($elapsed -lt $maxWait) {
    $readyPods = kubectl get pods -n argocd --no-headers 2>&1 | Where-Object { $_ -match "Running" }
    $totalPods = kubectl get pods -n argocd --no-headers 2>&1 | Measure-Object | Select-Object -ExpandProperty Count
    
    if ($readyPods.Count -eq $totalPods -and $totalPods -gt 0) {
        Write-Host "✓ All ArgoCD pods are ready" -ForegroundColor Green
        break
    }
    
    Write-Host "    Waiting... ($elapsed seconds elapsed)" -ForegroundColor Gray
    Start-Sleep -Seconds $interval
    $elapsed += $interval
}

if ($elapsed -ge $maxWait) {
    Write-Host "WARNING: Timeout waiting for pods. Check status manually:" -ForegroundColor Yellow
    Write-Host "    kubectl get pods -n argocd" -ForegroundColor Gray
}

# Step 5: Display pod status
Write-Host "[5/6] ArgoCD pod status:" -ForegroundColor Yellow
kubectl get pods -n argocd

# Step 6: Retrieve admin password
Write-Host ""
Write-Host "[6/6] Retrieving ArgoCD admin password..." -ForegroundColor Yellow
try {
    $password = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>&1
    if ($password) {
        $decodedPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($password))
        Write-Host "✓ Admin password retrieved" -ForegroundColor Green
        Write-Host ""
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host "ArgoCD Installation Complete!" -ForegroundColor Green
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Access Information:" -ForegroundColor Yellow
        Write-Host "  URL:      https://localhost:8080" -ForegroundColor White
        Write-Host "  Username: admin" -ForegroundColor White
        Write-Host "  Password: $decodedPassword" -ForegroundColor White
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "  1. Start port forwarding: kubectl port-forward svc/argocd-server -n argocd 8080:443" -ForegroundColor Gray
        Write-Host "  2. Open https://localhost:8080 in your browser" -ForegroundColor Gray
        Write-Host "  3. Login with the credentials above" -ForegroundColor Gray
        Write-Host "  4. Fork the starter repository (see SETUP_GUIDE.md)" -ForegroundColor Gray
        Write-Host "  5. Update and apply: breakout2/argocd/model-serving-app.yaml" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "WARNING: Could not retrieve password automatically" -ForegroundColor Yellow
        Write-Host "Run manually: argocd admin initial-password -n argocd" -ForegroundColor Gray
    }
} catch {
    Write-Host "WARNING: Could not retrieve password automatically" -ForegroundColor Yellow
    Write-Host "Run manually: argocd admin initial-password -n argocd" -ForegroundColor Gray
}

Write-Host "Installation log saved. Review SETUP_GUIDE.md for detailed instructions." -ForegroundColor Cyan
