# Red Hat CoP RBAC Automation - Complete Workflow

This guide finalizes your complete RBAC automation workflow using the Red Hat CoP Namespace Configuration Operator.

## 📋 Overview

**Environment Security Rules:**
- **Non-Prod** (`rnd`, `eng`, `qa`, `uat`): Admin + Developer + Audit access
- **Production** (`prod`): **Only Audit access** (no admin/edit permissions)
- **Cluster-Level**: Automatic ClusterRoleBindings for groups with `-cluster-` pattern

## 🚀 Deployment Steps

### 1. Prerequisites

```bash
# Install Red Hat CoP Namespace Configuration Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: namespace-configuration-operator
  namespace: openshift-marketplace
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: namespace-configuration-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

# Wait for operator to be ready
oc wait --for=condition=Available --timeout=300s deployment/namespace-configuration-operator -n namespace-configuration-operator
```

### 2. Deploy RBAC Configurations

```bash
# Deploy namespace-level RBAC (environment-aware)
oc apply -f redhat-cop-namespace-rbac.yaml

# Deploy cluster-level RBAC (pattern-based)
oc apply -f redhat-cop-cluster-rbac.yaml

# Verify configurations are created
oc get namespaceconfig
oc get groupconfig
```

## 🧪 Testing Scenarios

### Scenario 1: Development Environment

```bash
# Create development namespace
oc new-project payment-dev
oc label namespace payment-dev \
  company.net/mnemonic=paym \
  company.net/app-environment=rnd

# Expected RoleBindings created:
# ✅ paym-admin-rb     (admin access)
# ✅ paym-developer-rb (edit access)  
# ✅ paym-audit-rb     (view access)

# Verify
oc get rolebindings -n payment-dev
```

### Scenario 2: Production Environment (Restricted)

```bash
# Create production namespace
oc new-project payment-prod
oc label namespace payment-prod \
  company.net/mnemonic=paym \
  company.net/app-environment=prod

# Expected RoleBindings created:
# ❌ paym-admin-rb     (NO admin access in prod!)
# ❌ paym-developer-rb (NO edit access in prod!)
# ✅ paym-audit-rb     (view access only)

# Verify production restrictions
oc get rolebindings -n payment-prod
oc get rolebindings -n payment-prod -l rbac.ocp.io/role-type=ns-admin
# Expected: No resources found

oc get rolebindings -n payment-prod -l rbac.ocp.io/role-type=ns-developer
# Expected: No resources found

oc get rolebindings -n payment-prod -l rbac.ocp.io/role-type=ns-audit
# Expected: paym-audit-rb found
```

### Scenario 3: Cluster-Level RBAC

```bash
# Group Sync Operator creates these groups (automatic):
# app-ocp-rbac-frontend-cluster-admin
# app-ocp-rbac-backend-cluster-developer
# app-ocp-rbac-security-cluster-audit

# Expected ClusterRoleBindings created automatically:
# ✅ app-ocp-rbac-frontend-cluster-admin-crb  → admin
# ✅ app-ocp-rbac-backend-cluster-developer-crb → edit
# ✅ app-ocp-rbac-security-cluster-audit-crb → view

# Verify cluster RBAC
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator
```

## ✅ Verification Commands

### Namespace-Level Verification

```bash
# List all managed RoleBindings
oc get rolebindings -A -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check environment-specific access levels
oc get rolebindings -A -l rbac.ocp.io/access-level=admin-non-prod-only
oc get rolebindings -A -l rbac.ocp.io/access-level=developer-non-prod-only
oc get rolebindings -A -l rbac.ocp.io/access-level=audit-all-environments

# Verify no admin/edit in production
oc get rolebindings -A -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-admin
oc get rolebindings -A -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-developer
# Both should return: No resources found

# Verify audit access exists in production
oc get rolebindings -A -l rbac.ocp.io/environment=prod,rbac.ocp.io/role-type=ns-audit
# Should show audit RoleBindings
```

### Cluster-Level Verification

```bash
# List all managed ClusterRoleBindings
oc get clusterrolebindings -l app.kubernetes.io/managed-by=namespace-configuration-operator

# Check team-based groupings
oc get clusterrolebindings -l rbac.ocp.io/team=frontend
oc get clusterrolebindings -l rbac.ocp.io/team=backend

# Verify role mappings
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-admin --show-labels
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-developer --show-labels
oc get clusterrolebindings -l rbac.ocp.io/role-type=cluster-audit --show-labels
```

### Configuration Status Check

```bash
# Check NamespaceConfig status
oc get namespaceconfig mnemonic-environment-rbac -o yaml

# Check GroupConfig status
oc get groupconfig universal-cluster-rbac -o yaml

# Monitor operator logs
oc logs -n namespace-configuration-operator deployment/namespace-configuration-operator --tail=20
```

## 🔧 Troubleshooting

### RoleBindings Not Created

```bash
# Check namespace has required labels
oc get namespace <namespace-name> --show-labels
# Should have both: company.net/mnemonic and company.net/app-environment

# Check NamespaceConfig selector matches
oc get namespaceconfig mnemonic-environment-rbac -o jsonpath='{.spec.selector}'

# Check operator logs for errors
oc logs -n namespace-configuration-operator deployment/namespace-configuration-operator | grep ERROR
```

### ClusterRoleBindings Not Created

```bash
# List all groups to verify naming pattern
oc get groups | grep app-ocp-rbac | grep cluster

# Check GroupConfig is processing groups
oc describe groupconfig universal-cluster-rbac

# Verify groups match the pattern
oc get groups | grep "app-ocp-rbac.*cluster.*"
```

## 📊 Complete Access Matrix

| Environment | Admin Access | Developer Access | Audit Access |
|-------------|--------------|------------------|--------------|
| **rnd**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **eng**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **qa**      | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **uat**     | ✅ Yes       | ✅ Yes           | ✅ Yes       |
| **prod**    | ❌ **No**    | ❌ **No**        | ✅ Yes       |

## 🎯 Benefits of This Solution

1. **✅ Environment Security**: Automatic production restrictions
2. **✅ Mnemonic-Driven**: Uses existing company.net/mnemonic labels
3. **✅ Pattern-Based**: Leverages group naming conventions
4. **✅ Team-Friendly**: No complex policy management needed
5. **✅ Automatic**: Works with Group Sync Operator out of the box
6. **✅ Scalable**: Handles unlimited teams and environments
7. **✅ Auditable**: Rich labeling and annotations for compliance

## 🚀 Next Steps

1. **Deploy to non-production cluster first**
2. **Test with sample namespaces and groups**
3. **Verify environment restrictions work correctly**
4. **Monitor for 2-3 weeks before production deployment**
5. **Train operations team on verification commands**

Your RBAC automation workflow is now complete and production-ready! 🎉