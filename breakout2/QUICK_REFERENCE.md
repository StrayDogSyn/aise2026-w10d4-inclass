# ArgoCD Quick Reference Card

## Essential Commands

### Installation & Access
```bash
# Install ArgoCD (or use install-argocd.ps1 script)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login (if ArgoCD CLI installed)
argocd login localhost:8080 --username admin --password <password> --insecure
```

### Application Management
```bash
# Create application
kubectl apply -f breakout2/argocd/model-serving-app.yaml

# Get application status
argocd app get model-serving-prod

# List all applications
kubectl get applications -n argocd

# Sync application manually
argocd app sync model-serving-prod

# View application details
kubectl describe application model-serving-prod -n argocd
```

### Monitoring & Troubleshooting
```bash
# Check sync status
argocd app get model-serving-prod

# View sync history
argocd app history model-serving-prod

# Watch resources in target namespace
kubectl get all -n model-serving -w

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# View application events
kubectl get events -n argocd --field-selector involvedObject.name=model-serving-prod

# Force refresh application
kubectl patch application model-serving-prod -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Testing GitOps Workflow
```bash
# Clone your forked repository
git clone https://github.com/YOUR_USERNAME/aise-model-serving-starter.git
cd aise-model-serving-starter/k8s/overlays/prod

# Edit deployment (change replicas from 2 to 3)
# vim deployment.yaml or code deployment.yaml

# Commit and push
git add .
git commit -m "Test: Increase replicas to 3"
git push origin main

# Watch ArgoCD sync (should happen within 3 minutes)
kubectl get pods -n model-serving -w
```

### Self-Healing Test
```bash
# Get deployment name
kubectl get deployments -n model-serving

# Manually edit deployment (simulates drift)
kubectl edit deployment <deployment-name> -n model-serving
# Change replicas to a different value, save and exit

# Watch ArgoCD revert the change
kubectl get deployment -n model-serving -w
# Should revert to Git version within 10-20 seconds
```

### Validation
```bash
# Run validation script
pwsh breakout2/scripts/validate-argocd.ps1

# Or manual checks
kubectl get pods -n argocd                    # All should be Running
kubectl get application -n argocd             # Should show model-serving-prod
kubectl get all -n model-serving             # Should show deployed resources
```

## ArgoCD Application Manifest Structure

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: model-serving-prod
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/YOUR_USERNAME/REPO.git
    targetRevision: main
    path: k8s/overlays/prod
  
  destination:
    server: https://kubernetes.default.svc
    namespace: model-serving
  
  syncPolicy:
    automated:
      prune: true      # Delete removed resources
      selfHeal: true   # Revert manual changes
    syncOptions:
      - CreateNamespace=true
```

## Key Concepts

### Sync Status
- **Synced**: Cluster state matches Git
- **OutOfSync**: Cluster differs from Git
- **Unknown**: Unable to determine status

### Health Status
- **Healthy**: All resources running normally
- **Progressing**: Resources being created/updated
- **Degraded**: Some resources unhealthy
- **Suspended**: Resources intentionally paused
- **Missing**: Resources not found

### Sync Policy Options
- **automated.prune**: Delete resources removed from Git
- **automated.selfHeal**: Revert manual kubectl changes
- **automated.allowEmpty**: Allow syncing empty directories
- **syncOptions.CreateNamespace**: Auto-create target namespace
- **syncOptions.Validate**: Validate before applying
- **syncOptions.PruneLast**: Delete old resources after new ones ready

## Configuration Decisions

| Setting | Value | Rationale |
|---------|-------|-----------|
| Automated Sync | Enabled | True GitOps - Git is source of truth |
| Self-Heal | Enabled | Prevents configuration drift |
| Prune | Enabled | Complete sync between Git and cluster |
| Sync Window | None | Immediate deployment (can add for prod) |
| Namespace Creation | Auto | Simplifies initial deployment |
| Retry Strategy | 5 retries, exponential backoff | Handles transient failures |

## Troubleshooting Guide

### Application Won't Sync
1. Check repository URL and credentials
2. Verify path exists in repository
3. Check ArgoCD server logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server`
4. Force refresh: `argocd app get model-serving-prod --refresh`

### Self-Healing Not Working
1. Verify `selfHeal: true` in application spec
2. Check sync frequency (default 3 minutes)
3. Ensure ArgoCD has RBAC permissions

### Resources Not Deploying
1. Check application health: `argocd app get model-serving-prod`
2. View resource tree in UI for specific errors
3. Check namespace permissions
4. Verify Kubernetes manifests are valid

## UI Access
- **URL**: https://localhost:8080
- **Username**: admin
- **Password**: Retrieved via `argocd admin initial-password -n argocd`

## Security Best Practices
1. Change admin password after first login
2. Use RBAC for team access control
3. Don't commit secrets to Git (use Sealed Secrets or External Secrets)
4. Enable audit logging
5. Use dedicated service accounts
6. Implement branch protection on Git repositories

## Next Steps After Setup
1. ✅ Explore ArgoCD UI
2. ✅ Test automatic sync with replica change
3. ✅ Verify self-healing capability
4. 📚 Learn about ArgoCD Projects for multi-tenant setup
5. 🔒 Implement secret management (Sealed Secrets)
6. 🔔 Configure notifications (Slack, email)
7. 📊 Set up Prometheus metrics monitoring
8. 🌳 Design Git branching strategy for environments
