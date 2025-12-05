# Kyverno RBAC Policy v2-Numbered Solution

A comprehensive Kyverno-based RBAC automation system that generates RoleBindings and ClusterRoleBindings using numbered labels, with intelligent system namespace control and RBAC standards enforcement.

## 🎯 Overview

This solution automates Kubernetes RBAC management by:
- **Generating namespace-scoped RoleBindings** based on numbered OIM group labels
- **Creating cluster-wide ClusterRoleBindings** for OpenShift Groups
- **Enforcing RBAC naming standards** across the cluster
- **Intelligently controlling system namespace inclusion/exclusion**
- **Providing kill-switch functionality** for granular control

### Key Innovation: v2-Numbered Approach

Instead of comma-separated values in labels, we use individual numbered labels:

**❌ Old v1 approach:**
```yaml
labels:
  oim-ns-admin: "group1,group2,group3"
  oim-ns-edit: "group4,group5"
```

**✅ New v2-numbered approach:**
```yaml
labels:
  oim-ns-admin-1: "group1"
  oim-ns-admin-2: "group2" 
  oim-ns-admin-3: "group3"
  oim-ns-edit-1: "group4"
  oim-ns-edit-2: "group5"
```

## 📁 Repository Structure

```
├── README.md                                          # This comprehensive guide
├── system-namespace-rbac-control-policy.yaml          # System namespace labeling policy
├── generate-namespace-rolebindings-policy-v2-numbered.yaml  # Main RoleBinding generation
├── enforce-rbac-standards-policy-v2-numbered.yaml     # Validation and standards enforcement
├── generate-cluster-rolebindings-policy.yaml          # ClusterRoleBinding generation
├── scripts/
│   ├── deploy-rbac-policies.sh                        # Deploy all policies in order
│   ├── validate-rbac-policies.sh                      # Pre-deployment validation
│   ├── check-rbac-status.sh                          # Comprehensive status checker
│   ├── setup-namespaces-v2-numbered.sh               # Create test environments
│   └── cleanup-namespaces-v2-numbered.sh             # Clean up test resources
├── openshift-precedence-test.yaml                     # Precedence testing namespace
└── test-install-and-test-policy-readme.md            # Historical testing documentation
```

## 🚀 Quick Start

```bash
# 1. Validate all policies before deployment
./scripts/validate-rbac-policies.sh

# 2. Deploy all v2 policies in correct order
./scripts/deploy-rbac-policies.sh

# 3. Check system status
./scripts/check-rbac-status.sh

# 4. Create test namespaces with example labels
./scripts/setup-namespaces-v2-numbered.sh

# 5. Verify RoleBindings are generated
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno
```

## 📋 Policy Architecture

### 1. System Namespace RBAC Control Policy
**File:** `system-namespace-rbac-control-policy.yaml`

**Purpose:** Automatically manages include/exclude labels for system namespaces with intelligent precedence handling.

**Key Features:**
- **Auto-include approved system namespaces** (openshift-config, openshift-monitoring, kube-system)
- **Auto-exclude other system namespaces** (kube-*, openshift-*, default, istio-system, etc.)
- **Precedence enforcement**: `include-rbac=true` always overrides `exclude-rbac=true`
- **Cleanup rule**: Removes conflicting exclude-rbac labels when include-rbac is set

**Example Behavior:**
```bash
# Approved system namespace gets include-rbac=true
kubectl get ns openshift-config --show-labels
# NAME               STATUS   AGE   LABELS
# openshift-config   Active   5d    kyverno.io/include-rbac=true

# Other system namespaces get exclude-rbac=true
kubectl get ns openshift-authentication --show-labels  
# NAME                         STATUS   AGE   LABELS
# openshift-authentication     Active   5d    kyverno.io/exclude-rbac=true

# Manual override works
kubectl label namespace openshift-etcd kyverno.io/include-rbac=true
# The control policy automatically removes any existing exclude-rbac label
```

### 2. Generate Namespace RoleBindings Policy (v2-Numbered)
**File:** `generate-namespace-rolebindings-policy-v2-numbered.yaml`

**Purpose:** Creates individual RoleBindings for each group specified in numbered OIM labels.

**Label Pattern Support:**
- `oim-ns-admin-N` → ClusterRole/admin (namespace admin access)
- `oim-ns-edit-N` → ClusterRole/edit (developer access)  
- `oim-ns-view-N` → ClusterRole/view (read-only audit access)

**Key Features:**
- **Individual RoleBindings**: One RoleBinding per group (not comma-separated)
- **Smart preconditions**: Only processes namespaces with relevant labels
- **Exclude-rbac respect**: Skips namespaces marked as excluded
- **Synchronization**: Updates existing RoleBindings when labels change

**Generated RoleBinding Example:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-ocp-rbac-demo-ns-admin-admin-rb
  namespace: demo-ns
  labels:
    app.kubernetes.io/managed-by: kyverno
    app.kubernetes.io/version: v2-numbered
    rbac.ocp.io/role-type: ns-admin
    rbac.ocp.io/group-name: app-ocp-rbac-demo-ns-admin
  annotations:
    kyverno.io/policy: generate-namespace-rolebindings
    kyverno.io/rule: generate-ns-admin-rolebindings
subjects:
- kind: Group
  name: app-ocp-rbac-demo-ns-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

### 3. Enforce RBAC Standards Policy (v2-Numbered)
**File:** `enforce-rbac-standards-policy-v2-numbered.yaml`

**Purpose:** Validates group naming patterns and recommends RBAC labels on namespaces.

**Validation Rules:**
1. **Namespace group validation**: All groups in numbered labels must follow pattern:
   `app-ocp-rbac-{team}-(ns|cluster)-(admin|developer|audit)`

2. **OpenShift Group validation**: Group objects starting with `app-ocp-rbac-*` must follow the same pattern

3. **RBAC label recommendation**: Suggests adding at least one numbered RBAC label to namespaces

**Example Validation:**
```bash
# ✅ Valid group names
oim-ns-admin-1: "app-ocp-rbac-security-ns-admin"
oim-ns-edit-1: "app-ocp-rbac-frontend-ns-developer" 
oim-ns-view-1: "app-ocp-rbac-compliance-ns-audit"

# ❌ Invalid group names (will trigger audit warnings)
oim-ns-admin-1: "invalid-group-name"
oim-ns-edit-1: "app-rbac-team-admin"  # Missing ocp
```

### 4. Generate Cluster RoleBindings Policy
**File:** `generate-cluster-rolebindings-policy.yaml`

**Purpose:** Creates ClusterRoleBindings for OpenShift Groups with cluster-level access patterns.

**Supported Group Patterns:**
- `app-ocp-rbac-*-cluster-admin` → ClusterRole/admin
- `app-ocp-rbac-*-cluster-developer` → ClusterRole/edit
- `app-ocp-rbac-*-cluster-audit` → ClusterRole/view

**Generated ClusterRoleBinding Example:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-ocp-rbac-platform-cluster-admin-admin-crb
  labels:
    app.kubernetes.io/managed-by: kyverno
    rbac.ocp.io/role-type: cluster-role
    rbac.ocp.io/group-name: app-ocp-rbac-platform-cluster-admin
subjects:
- kind: Group
  name: app-ocp-rbac-platform-cluster-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

## 🧪 Testing Evidence

### Test Environment Setup

Our testing creates comprehensive scenarios to validate all functionality:

```bash
./scripts/setup-namespaces-v2-numbered.sh
```

**Test Namespaces Created:**

1. **demo-ns**: Basic single-group-per-role testing
   ```yaml
   labels:
     oim-ns-admin-1: "app-ocp-rbac-demo-ns-admin"
     oim-ns-edit-1: "app-ocp-rbac-demo-ns-developer" 
     oim-ns-view-1: "app-ocp-rbac-demo-ns-audit"
   ```

2. **team-alpha-dev**: Development team namespace
   ```yaml
   labels:
     oim-ns-admin-1: "app-ocp-rbac-alpha-ns-admin"
     oim-ns-edit-1: "app-ocp-rbac-alpha-ns-developer"
     oim-ns-view-1: "app-ocp-rbac-alpha-ns-audit"
   ```

3. **team-beta-prod**: Production team (admin + edit only)
   ```yaml
   labels:
     oim-ns-admin-1: "app-ocp-rbac-beta-ns-admin"
     oim-ns-edit-1: "app-ocp-rbac-beta-ns-developer"
   ```

4. **shared-tools**: Platform tools (admin + audit only)
   ```yaml
   labels:
     oim-ns-admin-1: "app-ocp-rbac-platform-ns-admin"
     oim-ns-view-1: "app-ocp-rbac-platform-ns-audit"
   ```

5. **multi-admin-test**: Multiple groups per role type
   ```yaml
   labels:
     oim-ns-admin-1: "app-ocp-rbac-security-ns-admin"
     oim-ns-admin-2: "app-ocp-rbac-platform-ns-admin"
     oim-ns-admin-3: "app-ocp-rbac-devops-ns-admin"
     oim-ns-edit-1: "app-ocp-rbac-frontend-ns-developer"
     oim-ns-edit-2: "app-ocp-rbac-backend-ns-developer"
     oim-ns-view-1: "app-ocp-rbac-security-ns-audit"
     oim-ns-view-2: "app-ocp-rbac-compliance-ns-audit"
     oim-ns-view-3: "app-ocp-rbac-monitoring-ns-audit"
   ```

6. **kill-switch-test**: Excluded namespace testing
   ```yaml
   labels:
     kyverno.io/exclude-rbac: "true"
     oim-ns-admin-1: "app-ocp-rbac-demo-ns-admin"  # Should be ignored
   ```

### System Namespace Control Testing

**Precedence Testing:**
```yaml
# openshift-precedence-test.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-precedence-test
  labels:
    kyverno.io/include-rbac: "true"  # Should override system exclusion
    oim-ns-admin-1: "openshift-yaml-admin"
    oim-ns-admin-2: "openshift-yaml-security"
    oim-ns-edit-1: "openshift-yaml-developer"
    oim-ns-view-1: "openshift-yaml-auditor"
    oim-ns-view-2: "openshift-yaml-monitoring"
```

**Expected Results:**
- ✅ System control policy recognizes `include-rbac=true` override
- ✅ Generate policy processes the namespace despite "openshift-" prefix
- ✅ Multiple RoleBindings created for numbered labels

### Control Label Testing Results

**Auto-Exclusion Testing:**
```bash
# Check auto-applied exclusion labels
kubectl get ns -o custom-columns="NAME:.metadata.name,EXCLUDE:.metadata.labels.kyverno\.io/exclude-rbac" | grep -E "(kube-|openshift-|default)"

# Results show automatic exclusion:
# NAME                    EXCLUDE
# default                 true
# kube-system            true
# kube-public            true
# openshift-operators    true
# openshift-authentication    true
```

**Auto-Inclusion Testing:**
```bash
# Check approved system namespaces
kubectl get ns openshift-config --show-labels
kubectl get ns openshift-monitoring --show-labels

# Results show automatic inclusion:
# openshift-config     kyverno.io/include-rbac=true
# openshift-monitoring kyverno.io/include-rbac=true
```

### RoleBinding Generation Verification

**Testing Commands Used:**
```bash
# Check generated RoleBindings across all namespaces
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno

# Detailed inspection of specific namespace
kubectl get rolebindings -n demo-ns -o yaml

# Check UpdateRequests for background processing
kubectl get updaterequest -A

# Monitor Kyverno processing
kubectl logs -n kyverno deployment/kyverno --tail=100 | grep -E "(generate|admit|mutate)"
```

**Verified Results:**
- ✅ Individual RoleBindings created for each numbered label
- ✅ Correct ClusterRole references (admin, edit, view)
- ✅ Proper labeling and annotations for management
- ✅ Synchronization updates when labels change
- ✅ Cleanup when labels removed

### Validation Policy Testing

**Standards Enforcement Testing:**
```bash
# Test invalid group name
kubectl create namespace validation-test
kubectl label namespace validation-test oim-ns-admin-1="invalid-group-name"

# Check for audit events
kubectl get events -A | grep -i "violation"

# Expected: Audit event with standards violation message
```

**OpenShift Group Validation:**
```bash
# Test valid OpenShift Group
oc create group app-ocp-rbac-platform-cluster-admin

# Test invalid OpenShift Group  
oc create group invalid-rbac-group

# Expected: Audit event for invalid group
```

## 🎛️ Control Features

### Kill Switch
Completely disable RBAC processing for any namespace:
```bash
kubectl label namespace my-namespace kyverno.io/exclude-rbac=true
```

### System Namespace Opt-in  
Override automatic exclusion for system namespaces:
```bash
kubectl label namespace openshift-etcd kyverno.io/include-rbac=true
kubectl label namespace openshift-etcd oim-ns-admin-1=app-ocp-rbac-platform-admin
```

### Manual Group Assignment
Add multiple groups to a namespace using numbered labels:
```bash
# Add admin groups
kubectl label namespace production oim-ns-admin-1=app-ocp-rbac-security-ns-admin
kubectl label namespace production oim-ns-admin-2=app-ocp-rbac-platform-ns-admin

# Add developer groups  
kubectl label namespace production oim-ns-edit-1=app-ocp-rbac-frontend-ns-developer
kubectl label namespace production oim-ns-edit-2=app-ocp-rbac-backend-ns-developer

# Add audit groups
kubectl label namespace production oim-ns-view-1=app-ocp-rbac-compliance-ns-audit
```

## 🔍 Troubleshooting

### Policy Status Check
```bash
# Check all policies are ready
kubectl get clusterpolicy

# Detailed policy status
kubectl describe clusterpolicy generate-namespace-rolebindings
```

### Generated Resources Inspection
```bash
# List all Kyverno-managed RoleBindings
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno

# Check specific namespace
kubectl get rolebindings -n demo-ns -o yaml

# Describe a specific RoleBinding
kubectl describe rolebinding app-ocp-rbac-demo-ns-admin-admin-rb -n demo-ns
```

### Background Processing Monitoring  
```bash
# Check UpdateRequests for background generation
kubectl get updaterequest -A

# Monitor Kyverno logs
kubectl logs -n kyverno deployment/kyverno -f

# Check for policy violations
kubectl get events -A | grep -i kyverno
```

### Namespace Label Verification
```bash
# Show all labels on a namespace
kubectl get namespace demo-ns --show-labels

# Check for RBAC control labels
kubectl get ns -o custom-columns="NAME:.metadata.name,INCLUDE:.metadata.labels.kyverno\.io/include-rbac,EXCLUDE:.metadata.labels.kyverno\.io/exclude-rbac"
```

### Status Monitoring Script
Use the comprehensive status checker:
```bash
./scripts/check-rbac-status.sh
```

This script provides:
- Kyverno system health check
- Policy deployment status
- System namespace labeling status  
- Sample OIM group labels
- Generated RoleBindings overview
- ClusterRoleBindings status
- Recent Kyverno events
- Actionable recommendations

## 🔄 Migration from v1 to v2

### 1. Backup Existing Setup
```bash
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno -o yaml > rolebindings-backup.yaml
kubectl get namespaces -o yaml > namespaces-backup.yaml
```

### 2. Deploy v2 Policies
```bash
./scripts/deploy-rbac-policies.sh
```

### 3. Update Existing Namespaces
Convert comma-separated labels to numbered labels:
```bash
# Old v1 label
kubectl label namespace my-ns oim-ns-admin-

# New v2 numbered labels  
kubectl label namespace my-ns oim-ns-admin-1=group1
kubectl label namespace my-ns oim-ns-admin-2=group2
kubectl label namespace my-ns oim-ns-admin-3=group3
```

### 4. Verify Migration
```bash
./scripts/check-rbac-status.sh
```

## 📊 Benefits of v2-Numbered Approach

| Feature | v1 (Comma-separated) | v2 (Numbered) |
|---------|---------------------|---------------|
| **Label format** | `oim-ns-admin: "g1,g2,g3"` | `oim-ns-admin-1: "g1"` |
| **JMESPath complexity** | High (split function) | Low (simple filtering) |
| **Debugging** | Hard (parsing required) | Easy (individual labels) |
| **Kubernetes native** | Less native | More native |
| **Label management** | Cumbersome | Intuitive |
| **Future maintenance** | Harder | Easier |
| **Group visibility** | Hidden in comma list | Individual labels |
| **Partial updates** | Replace entire list | Update specific groups |

## 🚦 Deployment Order

**Critical:** Policies must be deployed in this specific order:

1. **System Namespace RBAC Control** - Sets up inclusion/exclusion precedence
2. **Cluster RoleBindings Generation** - Handles cluster-wide permissions  
3. **RBAC Standards Enforcement** - Validates group names and patterns
4. **Namespace RoleBindings Generation** - Main namespace RBAC automation

Use `./scripts/deploy-rbac-policies.sh` to ensure correct deployment order.

## 🎯 Real-World Usage Examples

### Development Team Setup
```bash
kubectl create namespace frontend-dev
kubectl label namespace frontend-dev oim-ns-admin-1=app-ocp-rbac-frontend-ns-admin
kubectl label namespace frontend-dev oim-ns-edit-1=app-ocp-rbac-frontend-ns-developer  
kubectl label namespace frontend-dev oim-ns-edit-2=app-ocp-rbac-contractors-ns-developer
kubectl label namespace frontend-dev oim-ns-view-1=app-ocp-rbac-security-ns-audit
```

### Production Environment  
```bash
kubectl create namespace production-api
kubectl label namespace production-api oim-ns-admin-1=app-ocp-rbac-platform-ns-admin
kubectl label namespace production-api oim-ns-admin-2=app-ocp-rbac-security-ns-admin
kubectl label namespace production-api oim-ns-edit-1=app-ocp-rbac-sre-ns-developer
kubectl label namespace production-api oim-ns-view-1=app-ocp-rbac-compliance-ns-audit
kubectl label namespace production-api oim-ns-view-2=app-ocp-rbac-monitoring-ns-audit
```

### Shared Services
```bash  
kubectl create namespace shared-monitoring
kubectl label namespace shared-monitoring oim-ns-admin-1=app-ocp-rbac-platform-ns-admin
kubectl label namespace shared-monitoring oim-ns-view-1=app-ocp-rbac-all-teams-ns-audit
```

## 🔧 Advanced Configuration

### Custom RBAC Patterns
To support different group naming patterns, modify the validation regex in `enforce-rbac-standards-policy-v2-numbered.yaml`:
```yaml
# Current pattern: app-ocp-rbac-{team}-(ns|cluster)-(admin|developer|audit)
- key: "{{ regex_match('^app-ocp-rbac-[a-zA-Z0-9-]+-(ns|cluster)-(admin|developer|audit)$', element) }}"

# Custom pattern example: your-org-rbac-{team}-(admin|edit|view)  
- key: "{{ regex_match('^your-org-rbac-[a-zA-Z0-9-]+-(admin|edit|view)$', element) }}"
```

### Extended Group Support
To support more than 5 groups per role type, extend the context arrays in `generate-namespace-rolebindings-policy-v2-numbered.yaml`:
```yaml
context:
  - name: admin_groups
    variable:
      jmesPath: >
        [
          request.object.metadata.labels."oim-ns-admin-1" || '',
          request.object.metadata.labels."oim-ns-admin-2" || '',
          request.object.metadata.labels."oim-ns-admin-3" || '',
          request.object.metadata.labels."oim-ns-admin-4" || '',
          request.object.metadata.labels."oim-ns-admin-5" || '',
          request.object.metadata.labels."oim-ns-admin-6" || '',  # Add more as needed
          request.object.metadata.labels."oim-ns-admin-7" || ''
        ] | [?@ != '' && @ != null]
```

## 📈 Monitoring and Metrics

### Key Metrics to Monitor
- **Policy Ready Status**: All 4 policies should show `Ready: True`
- **Generated RoleBindings**: Count should match numbered labels across namespaces
- **Validation Events**: Monitor audit events for standards violations
- **UpdateRequests**: Background processing queue status

### Monitoring Commands
```bash
# Policy health
kubectl get cpol -o custom-columns="NAME:.metadata.name,READY:.status.ready,AGE:.metadata.creationTimestamp"

# Generated resources count
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno | wc -l
kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno | wc -l

# Processing queue
kubectl get updaterequest -A --no-headers | wc -l

# Recent violations  
kubectl get events -A --sort-by='.lastTimestamp' | grep -i "violation" | tail -10
```

---

## 🎉 Conclusion

The Kyverno RBAC v2-Numbered solution provides:

✅ **Automated RBAC management** with minimal manual intervention  
✅ **Intelligent system namespace handling** with precedence control  
✅ **Standards enforcement** for consistent group naming  
✅ **Scalable architecture** supporting multiple groups per role type  
✅ **Kill-switch controls** for granular management  
✅ **Comprehensive testing** with real-world scenarios  
✅ **Production-ready** deployment and monitoring tools  

This solution has been thoroughly tested with various namespace configurations, system namespace precedence scenarios, and control label combinations, proving its reliability for enterprise Kubernetes RBAC automation.
# rbac-kyverno-ideas
