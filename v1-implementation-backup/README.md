# V1 Implementation Backup

This folder contains the original v1 implementation of the Kyverno RBAC system that used comma-separated values in labels.

## V1 Files Moved Here:

### Policies:
- `enforce-rbac-standards-policy-v1.yaml` - V1 validation policy
- `generate-namespace-rolebindings-policy-v1.yaml` - V1 generate policy for namespaces
- `generate-cluster-rolebindings-policy-v1.yaml` - V1 generate policy for cluster roles

### Scripts:
- `cleanup-namespaces-v1.sh` - V1 namespace cleanup
- `monitor-kyverno-rbac-v1.sh` - V1 monitoring script
- `setup-groups-v1.sh` - V1 group setup
- `setup-namespaces-v1.sh` - V1 namespace setup
- `watch-kyverno-rbac-v1.sh` - V1 watching script
- `cleanup-namespaces.sh` - Original cleanup script (v1)
- `monitor-kyverno-rbac.sh` - Original monitoring script (v1)
- `setup-groups.sh` - Original group setup script (v1)
- `setup-namespaces.sh` - Original namespace setup script (v1)
- `watch-kyverno-rbac.sh` - Original watching script (v1)

### Backup Files:
- `old-copy.yaml` - Working backup of generate policy used during debugging

## V1 vs V2 Key Differences:

**V1 (Comma-separated):**
```yaml
oim-ns-admin: "group1,group2,group3"
oim-ns-edit: "dev-team,qa-team"
oim-ns-view: "audit-team"
```

**V2 (Numbered labels):**
```yaml
oim-ns-admin-1: "group1"
oim-ns-admin-2: "group2"
oim-ns-admin-3: "group3"
oim-ns-edit-1: "dev-team"
oim-ns-edit-2: "qa-team"
oim-ns-view-1: "audit-team"
```

## Why V2 Was Needed:

1. **Kubernetes Label Validation**: Comma-separated values caused validation issues
2. **JMESPath Limitations**: Splitting strings was complex and unreliable
3. **Individual RoleBindings**: V2 creates one RoleBinding per group for better management
4. **Precedence System**: V2 includes sophisticated include/exclude RBAC precedence logic

## Migration Path:

The current main directory contains the V2 implementation with:
- Numbered label schema
- Precedence system with `kyverno.io/include-rbac` and `kyverno.io/exclude-rbac`
- System namespace control policy
- Natural flow approach for production deployment

This backup ensures V1 implementation is preserved for reference or rollback if needed.
