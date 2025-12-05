# ArgoCD Validation Script
# This script validates the complete ArgoCD setup and GitOps workflow

Write-Host "================================" -ForegroundColor Cyan
Write-Host "ArgoCD Validation Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

$passCount = 0
$failCount = 0
$warnCount = 0

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Test,
        [string]$SuccessMessage,
        [string]$FailureMessage,
        [bool]$Critical = $true
    )
    
    Write-Host "Testing: $Name..." -ForegroundColor Yellow
    try {
        $result = & $Test
        if ($result) {
            Write-Host "  ✓ PASS: $SuccessMessage" -ForegroundColor Green
            $script:passCount++
            return $true
        } else {
            if ($Critical) {
                Write-Host "  ✗ FAIL: $FailureMessage" -ForegroundColor Red
                $script:failCount++
            } else {
                Write-Host "  ⚠ WARN: $FailureMessage" -ForegroundColor Yellow
                $script:warnCount++
            }
            return $false
        }
    } catch {
        if ($Critical) {
            Write-Host "  ✗ FAIL: $FailureMessage" -ForegroundColor Red
            $script:failCount++
        } else {
            Write-Host "  ⚠ WARN: $FailureMessage" -ForegroundColor Yellow
            $script:warnCount++
        }
        return $false
    }
}

# Test 1: Cluster Connectivity
Test-Step -Name "Cluster Connectivity" -Test {
    $result = kubectl cluster-info 2>&1
    return $LASTEXITCODE -eq 0
} -SuccessMessage "Cluster is accessible" -FailureMessage "Cannot connect to cluster"

# Test 2: ArgoCD Namespace Exists
Test-Step -Name "ArgoCD Namespace" -Test {
    $result = kubectl get namespace argocd 2>&1
    return $LASTEXITCODE -eq 0
} -SuccessMessage "ArgoCD namespace exists" -FailureMessage "ArgoCD namespace not found"

# Test 3: ArgoCD Pods Running
Test-Step -Name "ArgoCD Pods Status" -Test {
    $pods = kubectl get pods -n argocd --no-headers 2>&1
    $runningPods = $pods | Where-Object { $_ -match "Running" }
    $totalPods = ($pods | Measure-Object).Count
    
    Write-Host "    Found $($runningPods.Count)/$totalPods pods running" -ForegroundColor Gray
    
    return ($runningPods.Count -eq $totalPods) -and ($totalPods -gt 0)
} -SuccessMessage "All ArgoCD pods are running" -FailureMessage "Some ArgoCD pods are not running"

# Test 4: ArgoCD Server Service
Test-Step -Name "ArgoCD Server Service" -Test {
    $result = kubectl get svc argocd-server -n argocd 2>&1
    return $LASTEXITCODE -eq 0
} -SuccessMessage "ArgoCD server service exists" -FailureMessage "ArgoCD server service not found"

# Test 5: ArgoCD Application CRD
Test-Step -Name "ArgoCD Application CRD" -Test {
    $result = kubectl get crd applications.argoproj.io 2>&1
    return $LASTEXITCODE -eq 0
} -SuccessMessage "Application CRD is installed" -FailureMessage "Application CRD not found"

# Test 6: Model Serving Application Exists
Test-Step -Name "Model Serving Application" -Test {
    $result = kubectl get application model-serving-prod -n argocd 2>&1
    return $LASTEXITCODE -eq 0
} -SuccessMessage "Application 'model-serving-prod' exists" -FailureMessage "Application not found (apply model-serving-app.yaml)" -Critical $false

# Test 7: Application Sync Status
Test-Step -Name "Application Sync Status" -Test {
    $app = kubectl get application model-serving-prod -n argocd -o json 2>&1 | ConvertFrom-Json
    $syncStatus = $app.status.sync.status
    
    Write-Host "    Sync Status: $syncStatus" -ForegroundColor Gray
    
    return $syncStatus -eq "Synced"
} -SuccessMessage "Application is synced" -FailureMessage "Application is not synced" -Critical $false

# Test 8: Application Health Status
Test-Step -Name "Application Health Status" -Test {
    $app = kubectl get application model-serving-prod -n argocd -o json 2>&1 | ConvertFrom-Json
    $healthStatus = $app.status.health.status
    
    Write-Host "    Health Status: $healthStatus" -ForegroundColor Gray
    
    return $healthStatus -eq "Healthy"
} -SuccessMessage "Application is healthy" -FailureMessage "Application is not healthy" -Critical $false

# Test 9: Model Serving Namespace
Test-Step -Name "Model Serving Namespace" -Test {
    $result = kubectl get namespace model-serving 2>&1
    return $LASTEXITCODE -eq 0
} -SuccessMessage "model-serving namespace exists" -FailureMessage "model-serving namespace not found" -Critical $false

# Test 10: Deployed Resources
Test-Step -Name "Deployed Resources" -Test {
    $deployments = kubectl get deployments -n model-serving --no-headers 2>&1
    $services = kubectl get services -n model-serving --no-headers 2>&1
    
    $depCount = ($deployments | Measure-Object).Count
    $svcCount = ($services | Measure-Object).Count
    
    Write-Host "    Deployments: $depCount, Services: $svcCount" -ForegroundColor Gray
    
    return ($depCount -gt 0)
} -SuccessMessage "Resources deployed in model-serving namespace" -FailureMessage "No resources found in model-serving namespace" -Critical $false

# Test 11: Automated Sync Enabled
Test-Step -Name "Automated Sync Configuration" -Test {
    $app = kubectl get application model-serving-prod -n argocd -o json 2>&1 | ConvertFrom-Json
    $automated = $app.spec.syncPolicy.automated
    
    if ($automated) {
        Write-Host "    Prune: $($automated.prune), SelfHeal: $($automated.selfHeal)" -ForegroundColor Gray
        return $true
    }
    return $false
} -SuccessMessage "Automated sync is configured" -FailureMessage "Automated sync not configured" -Critical $false

# Test 12: Self-Heal Enabled
Test-Step -Name "Self-Heal Configuration" -Test {
    $app = kubectl get application model-serving-prod -n argocd -o json 2>&1 | ConvertFrom-Json
    $selfHeal = $app.spec.syncPolicy.automated.selfHeal
    
    return $selfHeal -eq $true
} -SuccessMessage "Self-heal is enabled" -FailureMessage "Self-heal not enabled" -Critical $false

# Display Summary
Write-Host ""
Write-Host "================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ✓ Passed:  $passCount" -ForegroundColor Green
Write-Host "  ✗ Failed:  $failCount" -ForegroundColor Red
Write-Host "  ⚠ Warnings: $warnCount" -ForegroundColor Yellow
Write-Host ""

if ($failCount -eq 0) {
    if ($warnCount -eq 0) {
        Write-Host "🎉 All validations passed! ArgoCD setup is complete." -ForegroundColor Green
    } else {
        Write-Host "✓ Core setup complete. Review warnings above." -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ Some critical validations failed. Review errors above." -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Check pod logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server" -ForegroundColor Gray
    Write-Host "  2. Review SETUP_GUIDE.md for detailed instructions" -ForegroundColor Gray
    Write-Host "  3. Ensure forked repository URL is correct in model-serving-app.yaml" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443" -ForegroundColor Gray
Write-Host "  2. Test automatic sync by modifying replica count in Git" -ForegroundColor Gray
Write-Host "  3. Verify self-healing by manually editing a deployment" -ForegroundColor Gray
Write-Host "  4. Check sync status: argocd app get model-serving-prod" -ForegroundColor Gray
Write-Host ""
