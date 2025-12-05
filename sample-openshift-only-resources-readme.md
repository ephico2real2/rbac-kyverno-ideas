Here is an example of red hat openshift only resources: it shows how to manage this resources. So this is how we need to deal with use cases:

apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: <infrastructure_id> 

------

apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-infrastructurename
  annotations:
    policies.kyverno.io/title: Inject Infrastructure Name
    policies.kyverno.io/category: OpenShift
    policies.kyverno.io/severity: medium
    kyverno.io/kyverno-version: 1.10.0
    policies.kyverno.io/minversion: 1.10.0
    kyverno.io/kubernetes-version: "1.26"
    policies.kyverno.io/subject: MachineSet
    policies.kyverno.io/description: >-
      A required component of a MachineSet is the infrastructure name which is a random string
      created in a separate resource. It can be tedious or impossible to know this for each
      MachineSet created. This policy fetches the value of the infrastructure name from the
      Cluster resource and replaces all instances of TEMPLATE in a MachineSet with that name.
spec:
  rules:
  - name: replace-template
    match:
      any:
      - resources:
          kinds:
          - machine.openshift.io/v1beta1/MachineSet
          operations:
          - CREATE
    context:
    - name: cluster
      apiCall:
        urlPath: /apis/config.openshift.io/v1/infrastructures/cluster
    - name: infraid
      variable:
        jmesPath: cluster.status.infrastructureName
    mutate:
      patchesJson6902: |-
        - op: replace
          path: /metadata
          value: {{ replace_all(to_string(request.object.metadata),'TEMPLATE', infraid) }}
        - op: replace
          path: /spec
          value: {{ replace_all(to_string(request.object.spec),'TEMPLATE', infraid) }}


Namespace Management
OpenShift allows users to manage various aspects of their environments, such as creating namespaces self-service. By default, users can be given complete freedom or be entirely restricted in their rights. However, this freedom can lead to uncontrolled growth and potential security risks without proper policies.

A concrete example is enforcing naming conventions for namespaces. You can set policies to ensure that all new namespaces adhere to specific naming rules, such as requiring a particular prefix. For instance, DevOps teams can only create namespaces starting with their team identifier. Another example is using a postfix in the namespace name to trigger actions automatically. For instance, installing namespaced operators requires privileges that shouldn’t be given to regular users. 

Another example is a Kyverno policy automatically installing an operator based on the namespace name.It provides self-service capabilities to DevOps teams.

This example installs a keycloak operator in a namespace when the created namespace ends with -keycloak

apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
 name: rhbkeycloak-namespace
 annotations:
   policies.kyverno.io/title: Allowed Namespace Names for Regular Users
   policies.kyverno.io/description: |
     This policy adds an OperatorGroup, Subscription, several Roles, several Rolebindings, several NetworkPolicys to namespace ending with *-keycloak
spec:
 validationFailureAction: Enforce
 background: false

Definition of the policy

rules:
 - name: keycloak-operatorgroup
   context:
   - name: namespaceprefix
     variable:
       jmesPath: split(request.object.metadata.name, '-')[0]

The keycloak-operatorgroup rule starts with extracting the namespaceprefix from the namespace name

match:
     any:
     - resources:
         kinds:
           - Namespace
         names:
           - "*-keycloak"

The rules matches any create namespace event where the namespace ends with -keycloak

preconditions:
     all:
     - key: "{{ namespaceprefix }}"
       operator: AnyNotIn
       value:
       - openshift
       - default
     - key: "{{ request.operation }}"
        operator: Equals
        value: CREATE

The rule must not match any namespace that starts with openshift or default

generate:
     apiVersion: operators.coreos.com/v1
     kind: OperatorGroup
     name: "{{ namespaceprefix }}-keycloak"
     namespace: "{{request.object.metadata.name}}"
     data:
       spec:
         targetNamespaces:
           - "{{request.object.metadata.name}}"

Generate an OperatorGroup resource when all conditions are met.

generate:
     apiVersion: "operators.coreos.com/v1alpha1"
     kind: Subscription
     name: "{{ namespaceprefix }}-rhsso-operator"
     namespace: "{{request.object.metadata.name}}"
     data:
       spec:
         channel: "{{ kyvernoparameters.data.keycloakchannel }}"
         installPlanApproval: Automatic
         name: keycloak-operator
         source: redhat-operators
         sourceNamespace: openshift-marketplace

Each generate rule must have its own set of match rules. Therefore, this generate rule has the same match rules as the generate OperatorGroup rule.

