Absolutely — here are **all** the extra resources you asked for:

* **4 CleanupPolicies** (Kyverno ≥ 1.12) to safely prune anything Kyverno generated when it’s no longer desired:

  * One **Namespace RoleBindings** cleanup (covers admin/edit/view in one policy).
  * Three **ClusterRoleBinding** cleanups (admin / developer→edit / audit→view), with mapping sanity checks.
* Nothing else is required—your existing `kyverno:rbac-generatecontroller` already has the verbs to delete RB/CRBs and read Namespaces/Groups.

> Heads-up: verify the CleanupPolicy apiVersion in your cluster (`kubectl api-resources | grep -i cleanup`). If your Kyverno shows a different version, just change `apiVersion` below accordingly.

---

```yaml
# ------------------------------------------------------------------------------
# CLEANUP: Namespace RoleBindings (admin/edit/view) — runs hourly
# Deletes RBs if:
#   - the namespace is system/infra AND not explicitly opted-in (exclude-rbac=false), OR
#   - exclude-rbac=true (kill switch), OR
#   - the RB's recorded group is no longer in the current namespace labels.
# Only touches Kyverno-generated RBs (managed-by=kyverno).
# ------------------------------------------------------------------------------
apiVersion: kyverno.io/v2alpha1   # <-- verify in your cluster
kind: CleanupPolicy
metadata:
  name: cleanup-orphaned-namespace-rolebindings
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-cleanup
spec:
  schedule: "0 * * * *"  # every hour
  match:
    any:
    - resources:
        kinds: ["RoleBinding"]
        namespaces: ["*"]
        selector:
          matchLabels:
            app.kubernetes.io/managed-by: kyverno
            # rbac.ocp.io/role-type will be one of ns-admin|ns-developer|ns-audit
            # we intentionally DO NOT lock it here to clean all three in one policy
  context:
  # Load the live Namespace and compute the list of current groups from labels
  - name: ns
    apiCall:
      urlPath: "/api/v1/namespaces/{{ request.object.metadata.namespace }}"
      jmesPath: "object"
  - name: current_groups
    variable:
      jmesPath: >
        split(
          regex_replace_all(
            to_string(join(',', [
              ns.metadata.labels."oim-ns-admin" || '',
              ns.metadata.labels."oim-ns-edit"  || '',
              ns.metadata.labels."oim-ns-view"  || ''
            ])),
            '\\s*[,]+\\s*', ','
          ),
          ','
        ) | [?@ != '']
  conditions:
    any:
    # (A) Kill switch anywhere
    - key: "{{ ns.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
      operator: Equals
      value: "true"

    # (B) System/infra namespace not explicitly opted-in with exclude-rbac=false
    - all:
      - key: "{{ ns.metadata.name }}"
        operator: Matches
        value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
      - key: "{{ ns.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
        operator: NotEquals
        value: "false"

    # (C) Group recorded on this RB is no longer present in current labels
    - key: "{{ request.object.metadata.labels.\"rbac.ocp.io/group-name\" || '' }}"
      operator: NotIn
      value: "{{ current_groups }}"
---
# ------------------------------------------------------------------------------
# CLEANUP: ClusterRoleBindings for cluster-admin — runs hourly (minute 10)
# Deletes CRB if the Group no longer exists OR name doesn't match pattern
# OR the roleRef isn't the expected 'admin'.
# ------------------------------------------------------------------------------
apiVersion: kyverno.io/v2alpha1
kind: CleanupPolicy
metadata:
  name: cleanup-orphaned-crb-admin
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-cleanup
spec:
  schedule: "10 * * * *"
  match:
    any:
    - resources:
        kinds: ["ClusterRoleBinding"]
        selector:
          matchLabels:
            app.kubernetes.io/managed-by: kyverno
            rbac.ocp.io/role-type: cluster-role
  context:
  - name: groupName
    variable:
      # Prefer the explicit label we stamp; fall back to CRB name if needed
      jmesPath: "request.object.metadata.labels.\"rbac.ocp.io/group-name\" || request.object.metadata.name"
  - name: group
    apiCall:
      urlPath: "/apis/user.openshift.io/v1/groups/{{ groupName }}"
      jmesPath: "object"
  conditions:
    any:
    # Group fetch failed (doesn't exist)
    - key: "{{ group.metadata.name || '' }}"
      operator: Equals
      value: ""
    # Group name no longer follows your pattern for cluster-admin
    - key: "{{ groupName }}"
      operator: NotMatches
      value: "^app-ocp-rbac-[a-z0-9-]+-cluster-admin$"
    # Mapping drift: admin CRB must reference ClusterRole 'admin'
    - key: "{{ request.object.roleRef.name || '' }}"
      operator: NotEquals
      value: "admin"
---
# ------------------------------------------------------------------------------
# CLEANUP: ClusterRoleBindings for cluster-developer → edit — runs hourly (min 20)
# Deletes CRB if the Group no longer exists OR name doesn't match pattern
# OR the roleRef isn't the expected 'edit'.
# ------------------------------------------------------------------------------
apiVersion: kyverno.io/v2alpha1
kind: CleanupPolicy
metadata:
  name: cleanup-orphaned-crb-developer
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-cleanup
spec:
  schedule: "20 * * * *"
  match:
    any:
    - resources:
        kinds: ["ClusterRoleBinding"]
        selector:
          matchLabels:
            app.kubernetes.io/managed-by: kyverno
            rbac.ocp.io/role-type: cluster-role
  context:
  - name: groupName
    variable:
      jmesPath: "request.object.metadata.labels.\"rbac.ocp.io/group-name\" || request.object.metadata.name"
  - name: group
    apiCall:
      urlPath: "/apis/user.openshift.io/v1/groups/{{ groupName }}"
      jmesPath: "object"
  conditions:
    any:
    - key: "{{ group.metadata.name || '' }}"
      operator: Equals
      value: ""
    - key: "{{ groupName }}"
      operator: NotMatches
      value: "^app-ocp-rbac-[a-z0-9-]+-cluster-developer$"
    # Mapping drift: developer CRB must reference ClusterRole 'edit'
    - key: "{{ request.object.roleRef.name || '' }}"
      operator: NotEquals
      value: "edit"
---
# ------------------------------------------------------------------------------
# CLEANUP: ClusterRoleBindings for cluster-audit → view — runs hourly (min 30)
# Deletes CRB if the Group no longer exists OR name doesn't match pattern
# OR the roleRef isn't the expected 'view'.
# ------------------------------------------------------------------------------
apiVersion: kyverno.io/v2alpha1
kind: CleanupPolicy
metadata:
  name: cleanup-orphaned-crb-audit
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-cleanup
spec:
  schedule: "30 * * * *"
  match:
    any:
    - resources:
        kinds: ["ClusterRoleBinding"]
        selector:
          matchLabels:
            app.kubernetes.io/managed-by: kyverno
            rbac.ocp.io/role-type: cluster-role
  context:
  - name: groupName
    variable:
      jmesPath: "request.object.metadata.labels.\"rbac.ocp.io/group-name\" || request.object.metadata.name"
  - name: group
    apiCall:
      urlPath: "/apis/user.openshift.io/v1/groups/{{ groupName }}"
      jmesPath: "object"
  conditions:
    any:
    - key: "{{ group.metadata.name || '' }}"
      operator: Equals
      value: ""
    - key: "{{ groupName }}"
      operator: NotMatches
      value: "^app-ocp-rbac-[a-z0-9-]+-cluster-audit$"
    # Mapping drift: audit CRB must reference ClusterRole 'view'
    - key: "{{ request.object.roleRef.name || '' }}"
      operator: NotEquals
      value: "view"
```

### Notes & tips

* These policies only touch objects with `app.kubernetes.io/managed-by=kyverno` — so **manually created** RB/CRBs won’t be touched.
* The **namespace** cleanup also honors your **3-state toggle**:

  * If a namespace is **system** and not explicitly opted in (`exclude-rbac=false`), cleanup will remove any leftover generated RBs.
  * If **exclude-rbac=true**, cleanup will remove generated RBs, even in non-system namespaces.
  * If a team’s group is removed from labels, the corresponding RB is deleted on the next run.
* Schedules are **staggered** (00/10/20/30) to avoid bursts. Adjust as you like.


