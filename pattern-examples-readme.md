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
