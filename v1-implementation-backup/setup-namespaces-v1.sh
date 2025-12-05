#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setting up Test Namespaces for Kyverno RBAC Testing ===${NC}"

# Function to setup namespace configuration
setup_namespace_configs() {
    # demo-ns
    create_namespace_with_labels "demo-ns" "app-ocp-rbac-demo-ns-admin,app-ocp-rbac-demo-ns-developer,app-ocp-rbac-demo-ns-audit"
    
    # team-alpha-dev  
    create_namespace_with_labels "team-alpha-dev" "app-ocp-rbac-alpha-ns-admin,app-ocp-rbac-alpha-ns-developer,app-ocp-rbac-alpha-ns-audit"
    
    # team-beta-prod
    create_namespace_with_labels "team-beta-prod" "app-ocp-rbac-beta-ns-admin,app-ocp-rbac-beta-ns-developer"
    
    # shared-tools
    create_namespace_with_labels "shared-tools" "app-ocp-rbac-platform-ns-admin,app-ocp-rbac-platform-ns-audit"
}

# Function to create namespace with labels
create_namespace_with_labels() {
    local ns_name=$1
    local groups=$2
    
    echo -e "${YELLOW}Creating namespace: ${ns_name}${NC}"
    
    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$ns_name" >/dev/null 2>&1; then
        kubectl create namespace "$ns_name"
        echo -e "${GREEN}✓ Namespace '$ns_name' created${NC}"
    else
        echo -e "${YELLOW}⚠ Namespace '$ns_name' already exists${NC}"
    fi
    
    # Parse groups and apply labels
    IFS=',' read -ra GROUP_ARRAY <<< "$groups"
    
    # Apply RBAC labels based on group suffixes
    for group in "${GROUP_ARRAY[@]}"; do
        if [[ $group == *"-admin" ]]; then
            kubectl label namespace "$ns_name" oim-ns-admin="$group" --overwrite
            echo -e "${GREEN}✓ Added admin label: oim-ns-admin=$group${NC}"
        elif [[ $group == *"-developer" ]]; then
            kubectl label namespace "$ns_name" oim-ns-edit="$group" --overwrite
            echo -e "${GREEN}✓ Added edit label: oim-ns-edit=$group${NC}"
        elif [[ $group == *"-audit" ]]; then
            kubectl label namespace "$ns_name" oim-ns-view="$group" --overwrite
            echo -e "${GREEN}✓ Added view label: oim-ns-view=$group${NC}"
        fi
    done
    
    # Add managed-by label for tracking
    kubectl label namespace "$ns_name" app.kubernetes.io/managed-by=kyverno-test --overwrite
    
    echo -e "${GREEN}✓ Namespace '$ns_name' configured successfully${NC}"
    echo ""
}

# Function to test opt-in/kill-switch functionality
setup_control_examples() {
    echo -e "${BLUE}=== Setting up Control Examples ===${NC}"
    
    # Example 1: Opt-in a system namespace (normally excluded)
    echo -e "${YELLOW}Setting up opt-in example for openshift-config namespace${NC}"
    if kubectl get namespace openshift-config >/dev/null 2>&1; then
        kubectl label namespace openshift-config kyverno.io/exclude-rbac=false --overwrite
        kubectl label namespace openshift-config oim-ns-admin=app-ocp-rbac-platform-ns-admin --overwrite
        echo -e "${GREEN}✓ openshift-config namespace opted-in with exclude-rbac=false${NC}"
    else
        echo -e "${YELLOW}⚠ openshift-config namespace not found (not OpenShift cluster?)${NC}"
    fi
    
    # Example 2: Create a namespace with kill-switch enabled
    echo -e "${YELLOW}Creating kill-switch example namespace${NC}"
    if ! kubectl get namespace kill-switch-test >/dev/null 2>&1; then
        kubectl create namespace kill-switch-test
    fi
    kubectl label namespace kill-switch-test kyverno.io/exclude-rbac=true --overwrite
    kubectl label namespace kill-switch-test oim-ns-admin=app-ocp-rbac-demo-ns-admin --overwrite
    kubectl label namespace kill-switch-test app.kubernetes.io/managed-by=kyverno-test --overwrite
    echo -e "${GREEN}✓ kill-switch-test namespace created with exclude-rbac=true${NC}"
    
    echo ""
}

# Function to verify namespace setup
verify_setup() {
    echo -e "${BLUE}=== Verifying Namespace Setup ===${NC}"
    
    echo -e "${YELLOW}Namespaces with RBAC labels:${NC}"
    kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --show-labels
    
    echo ""
    echo -e "${YELLOW}Detailed namespace information:${NC}"
    for ns in "demo-ns" "team-alpha-dev" "team-beta-prod" "shared-tools" "kill-switch-test"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            echo -e "${BLUE}--- $ns ---${NC}"
            kubectl describe namespace "$ns" | grep -E "(Name:|Labels:)" || true
            echo ""
        fi
    done
}

# Main execution
main() {
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}ERROR: kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Connected to cluster: $(kubectl config current-context)${NC}"
    echo ""
    
    # Create all test namespaces
    setup_namespace_configs
    
    # Setup control examples
    setup_control_examples
    
    # Verify setup
    verify_setup
    
    echo -e "${GREEN}=== Namespace setup completed successfully! ===${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Run './scripts/setup-groups.sh' to create OpenShift Groups"
    echo "2. Apply Kyverno policies: kubectl apply -f *.yaml"
    echo "3. Wait a few minutes and check generated RoleBindings"
}

# Run main function
main "$@"
