# Kyverno RBAC Policy v2-Numbered Solution

This document describes the v2-numbered implementation of Kyverno policies for namespace RoleBinding generation, which uses numbered labels instead of comma-separated values.

## Overview

The v2-numbered approach solves the limitations of comma-separated label values by using multiple numbered labels for each role type:

**Old v1 approach:**
```yaml
labels:
  oim-ns-admin: "group1,group2,group3"
  oim-ns-edit: "group4,group5"
  oim-ns-view: "group6"
```

**New v2-numbered approach:**
```yaml
labels:
  oim-ns-admin-1: "group1"
  oim-ns-admin-2: "group2" 
  oim-ns-admin-3: "group3"
  oim-ns-edit-1: "group4"
  oim-ns-edit-2: "group5"
  oim-ns-view-1: "group6"
```

## Benefits of v2-Numbered Approach

1. **Cleaner JMESPath expressions**: No need for complex string splitting
2. **Better label management**: Each group gets its own label key
3. **Easier troubleshooting**: Individual group assignments are more visible
4. **Avoids comma-parsing issues**: No need to handle comma-separated parsing in JMESPath
5. **Future-proof**: Easier to extend and maintain

## Files in this Solution

### Policy Files
- `generate-namespace-rolebindings-policy-v2-numbered.yaml` - Main Kyverno ClusterPolicy for generating RoleBindings
- `enforce-rbac-standards-policy-v2-numbered.yaml` - Validation policy to enforce group naming standards

### Shell Scripts  
- `scripts/setup-namespaces-v2-numbered.sh` - Creates test namespaces with numbered labels
- `scripts/cleanup-namespaces-v2-numbered.sh` - Cleans up test environment (handles both v1 and v2 labels)
- `scripts/deploy-and-test.sh` - Automation script for deployment and testing
- `scripts/validate-rbac-policies.sh` - Validates Kyverno policies before deployment
- `scripts/deploy-rbac-policies.sh` - Deploys all V2 RBAC policies in correct order
- `scripts/check-rbac-status.sh` - Comprehensive status monitoring of the RBAC system

### Documentation
- `README-v2-numbered.md` - This file
- `README-v1.md` - Documentation for v1 implementation

## Usage

### Quick Start
```bash
# Validate policies before deployment
./scripts/validate-rbac-policies.sh

# Deploy all V2 policies in correct order
./scripts/deploy-rbac-policies.sh

# Check system status
./scripts/check-rbac-status.sh

# Test with sample namespaces
./scripts/setup-namespaces-v2-numbered.sh

# Legacy: Deploy and test v2-numbered solution
./scripts/deploy-and-test.sh v2

# Cleanup test environments
./scripts/cleanup-namespaces-v2-numbered.sh
```

### Manual Namespace Labeling
```bash
# Add multiple admin groups
kubectl label namespace my-namespace oim-ns-admin-1=app-ocp-rbac-team1-admin
kubectl label namespace my-namespace oim-ns-admin-2=app-ocp-rbac-team2-admin

# Add edit groups  
kubectl label namespace my-namespace oim-ns-edit-1=app-ocp-rbac-team1-developer
kubectl label namespace my-namespace oim-ns-edit-2=app-ocp-rbac-team2-developer

# Add view groups
kubectl label namespace my-namespace oim-ns-view-1=app-ocp-rbac-audit-team
```

## Policy Structure

## Policy Structure

### Generate Policy Rules

The v2-numbered generate policy contains three separate `generate` rules:

#### Admin Rule
- **Trigger**: Labels starting with `oim-ns-admin-`
- **JMESPath**: `keys(@)[?starts_with(@, 'oim-ns-admin-')] | map(&@.*, @)`
- **Generated Role**: ClusterRole/admin
- **RoleBinding naming**: `{namespace}-admin-{group}`

#### Edit Rule  
- **Trigger**: Labels starting with `oim-ns-edit-`
- **JMESPath**: `keys(@)[?starts_with(@, 'oim-ns-edit-')] | map(&@.*, @)`
- **Generated Role**: ClusterRole/edit
- **RoleBinding naming**: `{namespace}-edit-{group}`

#### View Rule
- **Trigger**: Labels starting with `oim-ns-view-`
- **JMESPath**: `keys(@)[?starts_with(@, 'oim-ns-view-')] | map(&@.*, @)`
- **Generated Role**: ClusterRole/view  
- **RoleBinding naming**: `{namespace}-view-{group}`

### Validation Policy Rules

The v2-numbered validation policy enforces naming standards:

#### Validate Namespace Groups
- **Validates**: All group names in numbered labels follow the pattern `app-ocp-rbac-{team}-(ns|cluster)-(admin|developer|audit)`
- **JMESPath**: Extracts all groups from numbered labels and validates each
- **Action**: Audit violations (configurable to enforce)

#### Validate OpenShift Groups
- **Validates**: OpenShift Group objects with names starting with `app-ocp-rbac-*`
- **Pattern**: Must follow `app-ocp-rbac-{team}-(ns|cluster)-(admin|developer|audit)`
- **Action**: Audit violations (configurable to enforce)

#### Require RBAC Labels
- **Recommends**: At least one numbered RBAC label should be present on namespaces
- **Check**: Counts admin, edit, and view numbered labels
- **Action**: Audit recommendation if no labels found

## Control Features

### Kill Switch
Disable policy processing for a namespace:
```bash
kubectl label namespace my-namespace kyverno.io/exclude-rbac=true
```

### System Namespace Opt-in
Enable processing for system namespaces (normally excluded):
```bash
kubectl label namespace openshift-config kyverno.io/exclude-rbac=false
kubectl label namespace openshift-config oim-ns-admin-1=app-ocp-rbac-platform-admin
```

## Generated Resources

For each numbered label, the policy generates a RoleBinding:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding  
metadata:
  name: demo-ns-admin-app-ocp-rbac-demo-ns-admin
  namespace: demo-ns
  labels:
    app.kubernetes.io/managed-by: kyverno
    kyverno.io/generated-by-kind: Namespace
    kyverno.io/generated-by-name: demo-ns
    rbac.oim.policy/version: v2-numbered
    rbac.oim.policy/role: admin
    rbac.oim.policy/group: app-ocp-rbac-demo-ns-admin
subjects:
- kind: Group
  name: app-ocp-rbac-demo-ns-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

## Troubleshooting

### Check Policy Status
```bash
kubectl get clusterpolicy generate-ns-rolebindings-v2-numbered
kubectl describe clusterpolicy generate-ns-rolebindings-v2-numbered
```

### Check Generated RoleBindings
```bash
# List all Kyverno-managed RoleBindings
kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno

# Check specific namespace
kubectl get rolebindings -n demo-ns -l app.kubernetes.io/managed-by=kyverno

# Describe a specific RoleBinding
kubectl describe rolebinding demo-ns-admin-app-ocp-rbac-demo-ns-admin -n demo-ns
```

### Check Kyverno Logs
```bash
kubectl logs -n kyverno deployment/kyverno --tail=50
```

### Verify Namespace Labels
```bash
kubectl get namespace demo-ns --show-labels
```

## Migration from v1 to v2

1. **Backup existing setup**:
   ```bash
   kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno -o yaml > rolebindings-backup.yaml
   kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test -o yaml > namespaces-backup.yaml
   ```

2. **Clean up v1 environment**:
   ```bash
   ./scripts/cleanup-namespaces-v1.sh
   ```

3. **Deploy v2 solution**:
   ```bash
   ./scripts/deploy-and-test.sh v2
   ```

4. **Update existing namespaces**: Convert comma-separated labels to numbered labels manually or with a script.

## Testing Examples

The test setup creates these namespaces with numbered labels:

- **demo-ns**: 1 admin, 1 edit, 1 view group
- **team-alpha-dev**: 1 admin, 1 edit, 1 view group  
- **team-beta-prod**: 1 admin, 1 edit group (no view)
- **shared-tools**: 1 admin, 1 view group (no edit)

Each should generate the appropriate RoleBindings automatically via Kyverno.

## Comparison with v1

| Feature | v1 (Comma-separated) | v2 (Numbered) |
|---------|---------------------|---------------|
| Label format | `oim-ns-admin: "g1,g2,g3"` | `oim-ns-admin-1: "g1"` |
| JMESPath complexity | High (split function) | Low (simple filtering) |
| Debugging | Hard (parsing required) | Easy (individual labels) |
| Kubernetes native | Less native | More native |
| Label management | Cumbersome | Intuitive |
| Future maintenance | Harder | Easier |

The v2-numbered approach is the recommended solution going forward.
