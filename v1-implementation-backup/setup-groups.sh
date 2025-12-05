#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Setting up OpenShift Groups for Kyverno RBAC Testing ===${NC}"

# Define namespace-scoped groups (will generate RoleBindings)
NS_GROUPS=(
    "app-ocp-rbac-demo-ns-admin"
    "app-ocp-rbac-demo-ns-developer"
    "app-ocp-rbac-demo-ns-audit"
    "app-ocp-rbac-alpha-ns-admin"
    "app-ocp-rbac-alpha-ns-developer"
    "app-ocp-rbac-alpha-ns-audit"
    "app-ocp-rbac-beta-ns-admin"
    "app-ocp-rbac-beta-ns-developer"
    "app-ocp-rbac-platform-ns-admin"
    "app-ocp-rbac-platform-ns-audit"
)

# Define cluster-scoped groups (will generate ClusterRoleBindings)
CLUSTER_GROUPS=(
    "app-ocp-rbac-demo-cluster-admin"
    "app-ocp-rbac-demo-cluster-developer"
    "app-ocp-rbac-demo-cluster-audit"
    "app-ocp-rbac-alpha-cluster-admin"
    "app-ocp-rbac-alpha-cluster-developer"
    "app-ocp-rbac-alpha-cluster-audit"
    "app-ocp-rbac-platform-cluster-admin"
    "app-ocp-rbac-platform-cluster-developer"
)

# Function to detect if we're on OpenShift
detect_platform() {
    if command -v oc &> /dev/null && oc api-resources | grep -q "user.openshift.io"; then
        echo "openshift"
    else
        echo "kubernetes"
    fi
}

# Function to create OpenShift Group
create_openshift_group() {
    local group_name=$1
    local group_type=$2  # "namespace" or "cluster"
    
    echo -e "${YELLOW}Creating ${group_type} group: ${group_name}${NC}"
    
    # Check if group already exists
    if oc get group "$group_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ Group '$group_name' already exists${NC}"
        return 0
    fi
    
    # Create the group using oc command
    oc adm groups new "$group_name"
    
    # Add labels for tracking
    oc label group "$group_name" app.kubernetes.io/managed-by=kyverno-test --overwrite
    oc label group "$group_name" rbac.ocp.io/group-type="$group_type" --overwrite
    
    echo -e "${GREEN}✓ Group '$group_name' created successfully${NC}"
}

# Function to create Kubernetes-compatible Group manifest (for non-OpenShift)
create_k8s_group_manifest() {
    local group_name=$1
    local group_type=$2
    
    echo -e "${YELLOW}Creating ${group_type} group manifest: ${group_name}${NC}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: user.openshift.io/v1
kind: Group
metadata:
  name: ${group_name}
  labels:
    app.kubernetes.io/managed-by: kyverno-test
    rbac.ocp.io/group-type: ${group_type}
users: []
EOF
    
    echo -e "${GREEN}✓ Group '$group_name' manifest applied${NC}"
}

# Function to add test users to groups (optional)
add_test_users() {
    echo -e "${BLUE}=== Adding Test Users to Groups (Optional) ===${NC}"
    
    # Only add users if running on OpenShift and users exist
    if [[ $PLATFORM == "openshift" ]]; then
        # Add some demo users to groups for testing (if they exist)
        local test_users=("testuser1" "testuser2" "admin")
        
        for user in "${test_users[@]}"; do
            if oc get user "$user" >/dev/null 2>&1; then
                echo -e "${YELLOW}Adding user '$user' to demo groups${NC}"
                oc adm groups add-users app-ocp-rbac-demo-ns-admin "$user" 2>/dev/null || true
                oc adm groups add-users app-ocp-rbac-demo-cluster-developer "$user" 2>/dev/null || true
                echo -e "${GREEN}✓ Added '$user' to demo groups${NC}"
            fi
        done
    else
        echo -e "${YELLOW}⚠ Test user assignment skipped (not OpenShift or users don't exist)${NC}"
    fi
    
    echo ""
}

# Function to verify group creation
verify_groups() {
    echo -e "${BLUE}=== Verifying Group Creation ===${NC}"
    
    echo -e "${YELLOW}Namespace-scoped groups:${NC}"
    for group in "${NS_GROUPS[@]}"; do
        if kubectl get group "$group" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $group${NC}"
        else
            echo -e "${RED}✗ $group${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}Cluster-scoped groups:${NC}"
    for group in "${CLUSTER_GROUPS[@]}"; do
        if kubectl get group "$group" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ $group${NC}"
        else
            echo -e "${RED}✗ $group${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}All kyverno-test groups:${NC}"
    kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l | xargs echo -e "${GREEN}Total groups created:${NC}"
}

# Function to show expected generated resources
show_expected_resources() {
    echo -e "${BLUE}=== Expected Generated Resources ===${NC}"
    echo -e "${YELLOW}After applying Kyverno policies, you should see:${NC}"
    echo ""
    echo -e "${GREEN}RoleBindings (namespace-scoped):${NC}"
    echo "- demo-ns: app-ocp-rbac-demo-ns-admin-admin-rb, app-ocp-rbac-demo-ns-developer-edit-rb, etc."
    echo "- team-alpha-dev: app-ocp-rbac-alpha-ns-admin-admin-rb, etc."
    echo "- team-beta-prod: app-ocp-rbac-beta-ns-admin-admin-rb, etc."
    echo "- shared-tools: app-ocp-rbac-platform-ns-admin-admin-rb, etc."
    echo ""
    echo -e "${GREEN}ClusterRoleBindings (cluster-scoped):${NC}"
    echo "- app-ocp-rbac-demo-cluster-admin-admin-crb"
    echo "- app-ocp-rbac-demo-cluster-developer-edit-crb"
    echo "- app-ocp-rbac-demo-cluster-audit-view-crb"
    echo "- (similar for alpha and platform teams)"
    echo ""
}

# Main execution
main() {
    # Detect platform
    PLATFORM=$(detect_platform)
    echo -e "${GREEN}✓ Detected platform: $PLATFORM${NC}"
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Connected to cluster: $(kubectl config current-context)${NC}"
    echo ""
    
    # Create namespace-scoped groups
    echo -e "${BLUE}=== Creating Namespace-scoped Groups ===${NC}"
    for group in "${NS_GROUPS[@]}"; do
        if [[ $PLATFORM == "openshift" ]]; then
            create_openshift_group "$group" "namespace"
        else
            create_k8s_group_manifest "$group" "namespace"
        fi
    done
    
    echo ""
    
    # Create cluster-scoped groups
    echo -e "${BLUE}=== Creating Cluster-scoped Groups ===${NC}"
    for group in "${CLUSTER_GROUPS[@]}"; do
        if [[ $PLATFORM == "openshift" ]]; then
            create_openshift_group "$group" "cluster"
        else
            create_k8s_group_manifest "$group" "cluster"
        fi
    done
    
    echo ""
    
    # Add test users (optional)
    add_test_users
    
    # Verify setup
    verify_groups
    
    # Show expected resources
    show_expected_resources
    
    echo -e "${GREEN}=== Group setup completed successfully! ===${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Apply Kyverno policies: kubectl apply -f *.yaml"
    echo "2. Wait a few minutes for background generation"
    echo "3. Check generated resources:"
    echo "   kubectl get rolebindings -A"
    echo "   kubectl get clusterrolebindings | grep kyverno"
}

# Run main function
main "$@"
