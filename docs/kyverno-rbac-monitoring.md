# Kyverno RBAC Monitoring Guide

## Overview
This guide provides comprehensive monitoring tools and commands for Kyverno's RBAC automation system that generates ClusterRoleBindings based on OpenShift Groups.

## Quick Reference Commands

### 1. Real-time RBAC Generation Monitoring
```bash
kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller -f | grep "ClusterRoleBinding"
```
**Purpose**: Watch live ClusterRoleBinding generation events
**What to look for**: `created generate target resource` messages

### 2. Policy Error Monitoring
```bash
kubectl get events --all-namespaces --field-selector reason=PolicyError -w
```
**Purpose**: Monitor for policy validation or execution errors in real-time
**What to look for**: Any events related to `generate-cluster-rolebindings` policy

### 3. Policy Status Check
```bash
kubectl get clusterpolicies generate-cluster-rolebindings -o yaml | grep -A3 "conditions"
```
**Purpose**: Verify policy is healthy and ready
**Expected**: `status: "True"`, `reason: "Succeeded"`, `message: "Ready"`

### 4. Resource Count Verification
```bash
kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers | wc -l
kubectl get groups.user.openshift.io --no-headers | grep "app-ocp-rbac" | wc -l
```
**Purpose**: Ensure 1:1 mapping between OpenShift Groups and generated ClusterRoleBindings
**Expected**: Equal counts

## Automated Monitoring Scripts

### 1. Comprehensive Health Check Script
```bash
./scripts/monitor-kyverno-rbac.sh
```

**Features:**
- ✅ Kyverno pod status verification
- ✅ Policy readiness validation  
- ✅ Recent error detection (last hour)
- ✅ Resource count mapping verification
- ✅ Recent generation activity analysis
- ✅ Overall health summary with issue count

**Configuration:**
- Namespace: `kyverno`
- Policy: `generate-cluster-rolebindings`
- Group pattern: `app-ocp-rbac`

### 2. Interactive Real-time Monitoring
```bash
./scripts/watch-kyverno-rbac.sh
```

**Menu Options:**
1. **Watch ClusterRoleBinding generation logs** - Live log streaming (press Enter to exit)
2. **Policy error analysis with timestamps** - Detailed error history with time analysis (press Enter to exit)
3. **Monitor resource counts** - 5-second refresh dashboard (press Enter to stop)
4. **Watch Kyverno pod status** - Pod health monitoring (press Enter to exit)
5. **Run full health check** - Execute comprehensive script
6. **Recent activity summary with timestamps** - Quick overview with proper timestamps
7. **Exit**

## Key Monitoring Indicators

### ✅ Healthy System Indicators
- All Kyverno pods in `Running` state
- Policy status: `Ready (Succeeded)`
- No recent PolicyError events
- Perfect 1:1 mapping: Groups = ClusterRoleBindings
- Recent generation activity in logs
- Health summary: "System is healthy - all checks passed"

### ⚠️ Warning Signs
- Resource count mismatch (Groups ≠ ClusterRoleBindings)
- Kyverno pods not running or restarting frequently
- Policy status not "Ready"
- Recent PolicyError events in last hour

### ❌ Critical Issues
- Multiple pod failures
- Policy validation errors
- RBAC permission errors
- No generation activity despite new groups

## Improved Error Analysis

### Policy Error Timestamp Analysis
The interactive monitoring tool (option 2) now provides detailed timestamp analysis:

- **Current time display**: Shows when analysis was run
- **Last error timestamp**: Exact time of most recent error
- **Recency indicators**: Color-coded based on how recent errors are
  - 🚨 **Red**: Very recent (seconds/minutes)
  - ⚠️ **Yellow**: Moderately recent (10+ minutes to hours)
  - 🕒 **Green**: Older errors (days ago)
- **Error timeline**: Shows last 3 errors with relative timestamps
- **Message truncation**: Prevents overwhelming output

### Example Output
```
Policy Error Monitoring
Current time: Sat Sep  6 22:09:29 CDT 2025

Historical Policy Errors for generate-cluster-rolebindings:

📅 Most recent error occurred: 91m ago
🕒 1 hours ago (older)

Error timeline (most recent first):
  [91m ago] [default] policy generate-cluster-rolebindings/generate-crb-admin error: clusterrolebindi...
  [80m ago] [default] policy generate-cluster-rolebindings/generate-crb-admin error: clusterrolebindi...
  [79m ago] [default] policy generate-cluster-rolebindings/generate-crb-admin error: clusterrolebindi...
```

## Understanding the Logs

### Successful Generation Log Entry
```
2025-09-07T02:30:40Z TRC github.com/kyverno/kyverno/pkg/background/generate/generator.go:167 > created generate target resource logger=background name=ur-9pnv2 policy=generate-cluster-rolebindings rule=generate-crb-admin target=rbac.authorization.k8s.io/v1/ClusterRoleBinding//app-ocp-rbac-demo-cluster-admin-admin-crb trigger=/app-ocp-rbac-demo-cluster-admin v=2
```

**Key Components:**
- `created generate target resource` - Successful generation
- `policy=generate-cluster-rolebindings` - Our policy name
- `rule=generate-crb-admin` - Specific rule that triggered
- `target=...ClusterRoleBinding//app-ocp-rbac-demo-cluster-admin-admin-crb` - Generated resource
- `trigger=/app-ocp-rbac-demo-cluster-admin` - Source OpenShift Group

## Troubleshooting Common Issues

### Issue: ClusterRoleBindings Not Being Generated

**Check:**
1. Kyverno pods running: `kubectl get pods -n kyverno`
2. Policy status: `kubectl get clusterpolicies generate-cluster-rolebindings`
3. RBAC permissions: Look for "forbidden" errors in events
4. Group naming: Verify groups match pattern `app-ocp-rbac-*-cluster-*`

**Solutions:**
1. Restart Kyverno pods if needed
2. Verify aggregated ClusterRole permissions
3. Check policy syntax for Kyverno v1.15+ compatibility

### Issue: Resource Count Mismatch

**Causes:**
- Eventual consistency delays
- Policy errors during generation
- Manual deletion of resources
- Group creation/deletion timing

**Solutions:**
- Wait 1-2 minutes for background sync
- Check recent policy errors
- Verify group labels match policy selector

## Manual Validation Commands

```bash
# List all relevant groups
kubectl get groups.user.openshift.io | grep app-ocp-rbac

# List all generated ClusterRoleBindings
kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno

# Check specific ClusterRoleBinding details
kubectl describe clusterrolebinding app-ocp-rbac-{team}-cluster-{role}-{permission}-crb

# View policy details
kubectl get clusterpolicy generate-cluster-rolebindings -o yaml

# Check background controller logs (last 50 lines)
kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller --tail=50
```

## Alerting Recommendations

Set up alerts for:
- Kyverno pod failures or restarts
- Policy status changes from "Ready"
- PolicyError events related to RBAC generation
- Resource count mismatches lasting > 5 minutes
- No generation activity for > 10 minutes when groups exist

## Performance Monitoring

- **Generation latency**: Time between group creation and ClusterRoleBinding creation
- **Resource churn**: Frequency of generation/deletion cycles  
- **Log volume**: Background controller log growth rate
- **API server load**: Impact of Kyverno RBAC operations

This monitoring setup provides comprehensive visibility into your Kyverno RBAC automation system's health, performance, and troubleshooting capabilities.
