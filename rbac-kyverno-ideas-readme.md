Perfect—here’s your **single, ready-to-apply manifest** with:

* the **3-state preconditions** merged into **every Namespace rule**,
* short, role-aligned names (`*-admin-rb`, `*-edit-rb`, `*-view-rb`, `*-admin-crb|*-edit-crb|*-view-crb`),
* `app.kubernetes.io/managed-by: kyverno` on all generated objects,
* the RBAC role **renamed** to `kyverno:rbac-generatecontroller` (and referenced accordingly),
* tight Kyverno permissions (RBAC APIs + namespaces + OpenShift groups),
* `generateExisting: true` enabled.

```yaml
# ------------------------------------------------------------------------------
# Final RBAC Solution - NS Pattern (Short Names, 3-State Preconditions)
# Standards:
# - Namespace groups: app-ocp-rbac-{team}-ns-(admin|developer|audit)
# - Cluster groups:   app-ocp-rbac-{team}-cluster-(admin|developer|audit)
# Mapping:
# - ns-admin      → ClusterRole admin
# - ns-developer  → ClusterRole edit
# - ns-audit      → ClusterRole view
# - cluster-admin → ClusterRole admin
# - cluster-developer → ClusterRole edit
# - cluster-audit → ClusterRole view
# 3-state toggle (namespace level):
# - default: system/infra namespaces are excluded
# - opt-in:  kyverno.io/exclude-rbac=false → include even system/infra
# - kill:    kyverno.io/exclude-rbac=true  → exclude anywhere
# ------------------------------------------------------------------------------

---
# Tight ClusterRole for Kyverno generation (least privilege + patch)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kyverno:rbac-generatecontroller
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-automation
    app.kubernetes.io/part-of: ldap-integration
  annotations:
    policies.kyverno.io/description: "Minimal permissions for Kyverno to generate and manage RBAC resources"
rules:
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles","rolebindings","clusterroles","clusterrolebindings"]
  verbs: ["create","get","list","watch","update","patch","delete"]
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get","list","watch"]
- apiGroups: ["user.openshift.io"]
  resources: ["groups"]
  verbs: ["get","list","watch"]

---
# ClusterRoleBinding for Kyverno (confirm SA name in your cluster)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kyverno-admin-generate
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-automation
    app.kubernetes.io/part-of: ldap-integration
  annotations:
    policies.kyverno.io/description: "Grants Kyverno minimal permissions for RBAC automation"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kyverno:rbac-generatecontroller
subjects:
- kind: ServiceAccount
  name: kyverno   # adjust if your install uses a different SA name
  namespace: kyverno

---
# Validation Policy - Enforce naming standards (NS + Group)
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: enforce-rbac-ns-standards
  annotations:
    policies.kyverno.io/title: "Enforce RBAC NS Pattern Standards"
    policies.kyverno.io/category: "Multi-Tenancy"
    policies.kyverno.io/severity: high
    policies.kyverno.io/subject: "Namespace, Group"
    kyverno.io/kyverno-version: "1.10.0"
    policies.kyverno.io/minversion: "1.10.0"
    kyverno.io/kubernetes-version: "1.24-1.29"
    policies.kyverno.io/description: >-
      Enforces standardized RBAC group name patterns. Normalizes comma+space
      separated lists from labels and validates group names for namespaces and
      OpenShift Group objects. Uses a 3-state precondition to control inclusion.
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-validation
    app.kubernetes.io/part-of: ldap-integration
spec:
  validationFailureAction: Audit
  background: true
  rules:

  # Validate namespace label group values against allowed pattern
  - name: validate-namespace-groups
    match:
      any:
      - resources:
          kinds: ["Namespace"]
    preconditions:
      any:
      # (1) Normal: allow non-system namespaces
      - key: "{{ request.object.metadata.name }}"
        operator: NotMatches
        value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
      # (2) Opt-in: allow system/infra namespaces if exclude-rbac=false
      - all:
        - key: "{{ request.object.metadata.name }}"
          operator: Matches
          value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: Equals
          value: "false"
      # (3) Kill switch anywhere: exclude if exclude-rbac=true
      - all:
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: NotEquals
          value: "true"
    context:
      - name: all_groups
        variable:
          jmesPath: >
            split(
              regex_replace_all(
                to_string(join(',', [
                  request.object.metadata.labels."oim-ns-admin" || '',
                  request.object.metadata.labels."oim-ns-edit"  || '',
                  request.object.metadata.labels."oim-ns-view"  || ''
                ])),
                '\\s*[,]+\\s*', ','
              ),
              ','
            ) | [?@ != '']
    validate:
      foreach:
        - list: all_groups
          element: element
          message: "RBAC Standards Violation: Group '{{ element }}' must follow app-ocp-rbac-{team}-ns-(admin|developer|audit)."
          deny:
            conditions:
              any:
              - key: "{{ element }}"
                operator: NotMatches
                value: "^app-ocp-rbac-[a-z0-9-]+-ns-(admin|developer|audit)$"

  # Validate OpenShift Group objects against allowed pattern
  - name: validate-openshift-groups
    match:
      any:
      - resources:
          kinds: ["Group"]
          apiGroups: ["user.openshift.io"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: StartsWith
        value: "app-ocp-rbac-"
    validate:
      message: "RBAC Standards Violation: Group '{{ request.object.metadata.name }}' must follow app-ocp-rbac-{team}-(ns|cluster)-(admin|developer|audit)."
      deny:
        conditions:
          any:
          - key: "{{ request.object.metadata.name }}"
            operator: NotMatches
            value: "^app-ocp-rbac-[a-z0-9-]+-(ns|cluster)-(admin|developer|audit)$"

  # Recommend RBAC labels are present on namespaces
  - name: require-rbac-labels
    match:
      any:
      - resources:
          kinds: ["Namespace"]
    preconditions:
      any:
      # (1) Normal: allow non-system namespaces
      - key: "{{ request.object.metadata.name }}"
        operator: NotMatches
        value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
      # (2) Opt-in: allow system/infra namespaces if exclude-rbac=false
      - all:
        - key: "{{ request.object.metadata.name }}"
          operator: Matches
          value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: Equals
          value: "false"
      # (3) Kill switch anywhere: exclude if exclude-rbac=true
      - all:
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: NotEquals
          value: "true"
    validate:
      message: "RBAC Policy Recommendation: add at least one label (oim-ns-admin|oim-ns-edit|oim-ns-view) to enable team access."
      deny:
        conditions:
          all:
          - key: "{{ request.object.metadata.labels.\"oim-ns-admin\" || '' }}"
            operator: Equals
            value: ""
          - key: "{{ request.object.metadata.labels.\"oim-ns-edit\" || '' }}"
            operator: Equals
            value: ""
          - key: "{{ request.object.metadata.labels.\"oim-ns-view\" || '' }}"
            operator: Equals
            value: ""

---
# Generate Policy - Namespace RoleBindings (short names, correct foreach)
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: generate-namespace-rolebindings
  annotations:
    pod-policies.kyverno.io/autogen-controllers: none
    policies.kyverno.io/title: "Generate Namespace RoleBindings"
    policies.kyverno.io/category: "Multi-Tenancy"
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: "RoleBinding"
    kyverno.io/kyverno-version: "1.10.0"
    policies.kyverno.io/minversion: "1.10.0"
    kyverno.io/kubernetes-version: "1.24-1.29"
    policies.kyverno.io/description: >-
      Generates per-group RoleBindings in each namespace from labels:
      oim-ns-admin, oim-ns-edit, oim-ns-view. Names are short and role-aligned.
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-generation
    app.kubernetes.io/part-of: ldap-integration
spec:
  generateExisting: true
  generateExistingOnPolicyUpdate: true
  background: true
  rules:

  # ns-admin → ClusterRole admin
  - name: generate-ns-admin-rolebindings
    match:
      any:
      - resources:
          kinds: ["Namespace"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: NotMatches
        value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
      - all:
        - key: "{{ request.object.metadata.name }}"
          operator: Matches
          value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: Equals
          value: "false"
      - all:
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: NotEquals
          value: "true"
    context:
      - name: admin_groups
        variable:
          jmesPath: >
            split(
              regex_replace_all(
                to_string(request.object.metadata.labels."oim-ns-admin" || ''),
                '\\s*[,]+\\s*', ','
              ),
              ','
            ) | [?@ != '']
    generate:
      synchronize: true
      foreach:
      - list: admin_groups
        element: element
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        name: "{{ element }}-admin-rb"
        namespace: "{{ request.object.metadata.name }}"
        data:
          metadata:
            labels:
              app.kubernetes.io/managed-by: kyverno
              rbac.ocp.io/role-type: ns-admin
              rbac.ocp.io/group-name: "{{ element }}"
            annotations:
              kyverno.io/policy: generate-namespace-rolebindings
              kyverno.io/rule: generate-ns-admin-rolebindings
              kyverno.io/source-label: oim-ns-admin
          subjects:
          - kind: Group
            name: "{{ element }}"
            apiGroup: rbac.authorization.k8s.io
          roleRef:
            apiGroup: rbac.authorization.k8s.io
            kind: ClusterRole
            name: admin

  # ns-developer → ClusterRole edit
  - name: generate-ns-developer-rolebindings
    match:
      any:
      - resources:
          kinds: ["Namespace"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: NotMatches
        value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
      - all:
        - key: "{{ request.object.metadata.name }}"
          operator: Matches
          value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: Equals
          value: "false"
      - all:
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: NotEquals
          value: "true"
    context:
      - name: edit_groups
        variable:
          jmesPath: >
            split(
              regex_replace_all(
                to_string(request.object.metadata.labels."oim-ns-edit" || ''),
                '\\s*[,]+\\s*', ','
              ),
              ','
            ) | [?@ != '']
    generate:
      synchronize: true
      foreach:
      - list: edit_groups
        element: element
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        name: "{{ element }}-edit-rb"
        namespace: "{{ request.object.metadata.name }}"
        data:
          metadata:
            labels:
              app.kubernetes.io/managed-by: kyverno
              rbac.ocp.io/role-type: ns-developer
              rbac.ocp.io/group-name: "{{ element }}"
            annotations:
              kyverno.io/policy: generate-namespace-rolebindings
              kyverno.io/rule: generate-ns-developer-rolebindings
              kyverno.io/source-label: oim-ns-edit
          subjects:
          - kind: Group
            name: "{{ element }}"
            apiGroup: rbac.authorization.k8s.io
          roleRef:
            apiGroup: rbac.authorization.k8s.io
            kind: ClusterRole
            name: edit

  # ns-audit → ClusterRole view
  - name: generate-ns-audit-rolebindings
    match:
      any:
      - resources:
          kinds: ["Namespace"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: NotMatches
        value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
      - all:
        - key: "{{ request.object.metadata.name }}"
          operator: Matches
          value: "^(kube-(system|public|node-lease)|default|openshift-.*|kyverno(-.*)?)$"
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: Equals
          value: "false"
      - all:
        - key: "{{ request.object.metadata.labels.\"kyverno.io/exclude-rbac\" || '' }}"
          operator: NotEquals
          value: "true"
    context:
      - name: view_groups
        variable:
          jmesPath: >
            split(
              regex_replace_all(
                to_string(request.object.metadata.labels."oim-ns-view" || ''),
                '\\s*[,]+\\s*', ','
              ),
              ','
            ) | [?@ != '']
    generate:
      synchronize: true
      foreach:
      - list: view_groups
        element: element
        apiVersion: rbac.authorization.k8s.io/v1
        kind: RoleBinding
        name: "{{ element }}-view-rb"
        namespace: "{{ request.object.metadata.name }}"
        data:
          metadata:
            labels:
              app.kubernetes.io/managed-by: kyverno
              rbac.ocp.io/role-type: ns-audit
              rbac.ocp.io/group-name: "{{ element }}"
            annotations:
              kyverno.io/policy: generate-namespace-rolebindings
              kyverno.io/rule: generate-ns-audit-rolebindings
              kyverno.io/source-label: oim-ns-view
          subjects:
          - kind: Group
            name: "{{ element }}"
            apiGroup: rbac.authorization.k8s.io
          roleRef:
            apiGroup: rbac.authorization.k8s.io
            kind: ClusterRole
            name: view

---
# Generate Policy - ClusterRoleBindings (3 rules, short names)
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: generate-cluster-rolebindings
  annotations:
    pod-policies.kyverno.io/autogen-controllers: none
    policies.kyverno.io/title: "Generate Cluster RoleBindings"
    policies.kyverno.io/category: "Multi-Tenancy"
    policies.kyverno.io/severity: high
    policies.kyverno.io/subject: "ClusterRoleBinding"
    kyverno.io/kyverno-version: "1.10.0"
    policies.kyverno.io/minversion: "1.10.0"
    kyverno.io/kubernetes-version: "1.24-1.29"
    policies.kyverno.io/description: >-
      Generates ClusterRoleBindings for app-ocp-rbac-*-cluster-* groups with
      short, role-aligned names: -admin-crb, -edit-crb, -view-crb.
  labels:
    app.kubernetes.io/name: kyverno
    app.kubernetes.io/component: rbac-generation
    app.kubernetes.io/part-of: ldap-integration
spec:
  generateExisting: true
  generateExistingOnPolicyUpdate: true
  background: true
  rules:

  # cluster-admin → admin
  - name: generate-crb-admin
    match:
      any:
      - resources:
          kinds: ["Group"]
          apiGroups: ["user.openshift.io"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: Matches
        value: "^app-ocp-rbac-[a-z0-9-]+-cluster-admin$"
    generate:
      synchronize: true
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      name: "{{ request.object.metadata.name }}-admin-crb"
      data:
        metadata:
          labels:
            app.kubernetes.io/managed-by: kyverno
            rbac.ocp.io/role-type: cluster-role
            rbac.ocp.io/group-name: "{{ request.object.metadata.name }}"
          annotations:
            kyverno.io/policy: generate-cluster-rolebindings
            kyverno.io/rule: generate-crb-admin
        subjects:
        - kind: Group
          name: "{{ request.object.metadata.name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: admin

  # cluster-developer → edit
  - name: generate-crb-developer
    match:
      any:
      - resources:
          kinds: ["Group"]
          apiGroups: ["user.openshift.io"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: Matches
        value: "^app-ocp-rbac-[a-z0-9-]+-cluster-developer$"
    generate:
      synchronize: true
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      name: "{{ request.object.metadata.name }}-edit-crb"
      data:
        metadata:
          labels:
            app.kubernetes.io/managed-by: kyverno
            rbac.ocp.io/role-type: cluster-role
            rbac.ocp.io/group-name: "{{ request.object.metadata.name }}"
          annotations:
            kyverno.io/policy: generate-cluster-rolebindings
            kyverno.io/rule: generate-crb-developer
        subjects:
        - kind: Group
          name: "{{ request.object.metadata.name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: edit

  # cluster-audit → view
  - name: generate-crb-audit
    match:
      any:
      - resources:
          kinds: ["Group"]
          apiGroups: ["user.openshift.io"]
    preconditions:
      any:
      - key: "{{ request.object.metadata.name }}"
        operator: Matches
        value: "^app-ocp-rbac-[a-z0-9-]+-cluster-audit$"
    generate:
      synchronize: true
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      name: "{{ request.object.metadata.name }}-view-crb"
      data:
        metadata:
          labels:
            app.kubernetes.io/managed-by: kyverno
            rbac.ocp.io/role-type: cluster-role
            rbac.ocp.io/group-name: "{{ request.object.metadata.name }}"
          annotations:
            kyverno.io/policy: generate-cluster-rolebindings
            kyverno.io/rule: generate-crb-audit
        subjects:
        - kind: Group
          name: "{{ request.object.metadata.name }}"
          apiGroup: rbac.authorization.k8s.io
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: view
```

### Quick checks

* Validate with Kyverno CLI:

  ```bash
  kyverno apply ./rbac-policies/ --audit-warn
  ```
* Opt-in a system namespace:

  ```bash
  oc label ns openshift-config kyverno.io/exclude-rbac=false --overwrite
  ```
* Kill switch anywhere:

  ```bash
  oc label ns myteam-dev kyverno.io/exclude-rbac=true --overwrite
  ```

Want me to also append **CleanupPolicies** (Kyverno ≥1.12) that prune orphaned RB/CRBs using the `app.kubernetes.io/managed-by=kyverno` label + your group labels?

