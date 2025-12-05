# ArgoCD Setup and Validation Guide
# Complete step-by-step instructions for Breakout 2

## Prerequisites Checklist

Before starting, ensure you have:
- [ ] GKE cluster deployed and running (from Breakout 1)
- [ ] kubectl configured to access the cluster
- [ ] ArgoCD CLI installed (optional but recommended)
- [ ] Git repository access for forking
- [ ] GitHub account for repository management

## Step 1: Verify Cluster Connectivity

First, confirm your cluster is accessible:

```bash
# Get cluster credentials (if not already configured)
gcloud container clusters get-credentials prod-ml-cluster --region us-central1

# Verify connectivity
kubectl cluster-info

# Check available nodes
kubectl get nodes

# Expected output: You should see your CPU and GPU node pools
```

## Step 2: Install ArgoCD

Install ArgoCD into the cluster using the official manifests:

```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD components
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD pods to be ready (this may take 2-3 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Verify all ArgoCD pods are running
kubectl get pods -n argocd

# Expected output: All pods should show STATUS: Running
```

## Step 3: Access ArgoCD UI

Expose the ArgoCD server and retrieve credentials:

```bash
# Option 1: Port forward (for local access)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# In a separate terminal, retrieve the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access UI at: https://localhost:8080
# Username: admin
# Password: [output from above command]

# Option 2: ArgoCD CLI (if installed)
argocd admin initial-password -n argocd
```

## Step 4: Fork the Starter Repository

**IMPORTANT:** You need to fork the starter repository to have write access.

1. Navigate to the starter repository URL (provided by instructor)
   - Example: `https://github.com/AISE-Curriculum/aise-model-serving-starter`

2. Click the "Fork" button in the top-right corner

3. Select your GitHub account as the destination

4. Wait for the fork to complete

5. Copy your forked repository URL:
   - Format: `https://github.com/YOUR_USERNAME/aise-model-serving-starter`

## Step 5: Configure ArgoCD Application

Update the ArgoCD application manifest with your forked repository:

```bash
# Edit the application manifest
# Update the repoURL field with your forked repository URL
# File location: breakout2/argocd/model-serving-app.yaml

# After updating, apply the configuration
kubectl apply -f breakout2/argocd/model-serving-app.yaml

# Verify the application was created
kubectl get application -n argocd

# Expected output: model-serving-prod should appear
```

## Step 6: Verify Initial Sync

Check that ArgoCD has synced the manifests from Git:

```bash
# Using kubectl
kubectl get application model-serving-prod -n argocd -o yaml

# Using ArgoCD CLI (if installed)
argocd app get model-serving-prod

# Check deployed resources
kubectl get all -n model-serving

# Expected: You should see deployments, services, and pods
```

## Step 7: Test Automatic Synchronization

Modify a replica count in Git to test GitOps automation:

```bash
# 1. Clone your forked repository
git clone https://github.com/YOUR_USERNAME/aise-model-serving-starter.git
cd aise-model-serving-starter

# 2. Navigate to the production overlay
cd k8s/overlays/prod

# 3. Edit the deployment file (e.g., deployment.yaml)
# Find the line with 'replicas: 2' and change it to 'replicas: 3'

# 4. Commit and push the change
git add .
git commit -m "Test: Increase replicas from 2 to 3"
git push origin main

# 5. Watch ArgoCD sync automatically (within 3 minutes by default)
kubectl get pods -n model-serving -w

# 6. Verify the new replica count
kubectl get deployment -n model-serving

# Expected: Deployment should show 3/3 ready replicas
```

## Step 8: Test Self-Healing Capability

Verify that ArgoCD reverts manual changes:

```bash
# 1. Get the deployment name
kubectl get deployment -n model-serving

# 2. Manually edit the deployment (this simulates configuration drift)
kubectl edit deployment <deployment-name> -n model-serving

# In the editor, change replicas from 3 to 5, then save and exit

# 3. Check the current replicas
kubectl get deployment -n model-serving
# You'll briefly see 5 replicas

# 4. Wait 10-20 seconds and check again
kubectl get deployment -n model-serving
# ArgoCD should have reverted it back to 3 (matching Git)

# 5. Verify self-heal in ArgoCD
argocd app get model-serving-prod
# Check the sync status and recent activity
```

## Step 9: Validate Sync Status

Check the comprehensive sync status:

```bash
# Using ArgoCD CLI
argocd app get model-serving-prod

# Expected output should show:
# - Sync Status: Synced
# - Health Status: Healthy
# - Recent sync activity

# View sync history
argocd app history model-serving-prod

# Check for any sync errors
kubectl describe application model-serving-prod -n argocd
```

## Step 10: Access ArgoCD UI for Visual Validation

```bash
# Start port forwarding (if not already running)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser to https://localhost:8080
# Login with admin credentials

# In the UI, you should see:
# - Application: model-serving-prod
# - Status: Synced and Healthy (green checkmarks)
# - Resource tree showing all deployed resources
# - Sync history and events
```

## Troubleshooting Common Issues

### Issue: ArgoCD pods not starting
```bash
# Check pod logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Check resource availability
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-server
```

### Issue: Application not syncing
```bash
# Check application status
kubectl describe application model-serving-prod -n argocd

# Force a sync
argocd app sync model-serving-prod

# Or via kubectl
kubectl patch application model-serving-prod -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

### Issue: Self-healing not working
```bash
# Verify automated sync policy
kubectl get application model-serving-prod -n argocd -o jsonpath='{.spec.syncPolicy.automated}'

# Should show: {"prune":true,"selfHeal":true}
```

## Configuration Decisions Documentation

### Decision 1: Automated Sync Enabled
- **Rationale:** Enables true GitOps - changes in Git automatically deploy to cluster
- **Tradeoff:** Requires careful Git management; accidental commits deploy immediately
- **Alternative:** Manual sync for more control (not recommended for production)

### Decision 2: Self-Heal Enabled
- **Rationale:** Prevents configuration drift; maintains Git as single source of truth
- **Tradeoff:** Manual kubectl changes are reverted; requires Git workflow discipline
- **Benefit:** Ensures consistency and auditability

### Decision 3: Prune Enabled
- **Rationale:** Deleted resources in Git are removed from cluster
- **Tradeoff:** Can cause unexpected deletions if not careful
- **Benefit:** Complete synchronization between Git and cluster state

### Decision 4: Namespace Auto-Creation
- **Rationale:** ArgoCD creates namespace if missing
- **Benefit:** Simplifies initial deployment
- **Consideration:** Namespace configuration should be in Git for GitOps completeness

### Decision 5: Retry with Backoff
- **Rationale:** Handles transient failures gracefully
- **Configuration:** 5 retries with exponential backoff (5s to 3m)
- **Benefit:** Resilient to temporary cluster issues

## Validation Checklist

After completing all steps, verify:

- [ ] ArgoCD is installed and running (all pods healthy)
- [ ] ArgoCD UI is accessible
- [ ] Repository is forked and accessible
- [ ] Application is created in ArgoCD
- [ ] Initial sync completed successfully
- [ ] Resources deployed to model-serving namespace
- [ ] Automatic sync tested (replica change propagated)
- [ ] Self-healing verified (manual change reverted)
- [ ] Sync status shows "Synced" and "Healthy"
- [ ] Team members reviewed and validated configuration

## Additional Resources

- ArgoCD Documentation: https://argo-cd.readthedocs.io/
- GitOps Principles: https://www.gitops.tech/
- Troubleshooting Guide: https://argo-cd.readthedocs.io/en/stable/operator-manual/troubleshooting/

## Notes for Team Discussion

**Discuss with your group:**

1. How does GitOps change our deployment workflow?
2. What are the security implications of automated sync?
3. When might we want to disable self-healing temporarily?
4. How do we handle emergency hotfixes with GitOps?
5. What Git branching strategy works best with ArgoCD?
6. How do we manage secrets in a GitOps workflow?

**Production Considerations:**

1. Use dedicated Git projects for production deployments
2. Implement branch protection and PR reviews
3. Configure RBAC policies in ArgoCD
4. Set up notifications for sync failures
5. Implement proper secret management (Sealed Secrets, External Secrets)
6. Configure sync windows for controlled deployments
