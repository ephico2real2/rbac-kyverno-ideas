#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cleaning up OpenShift Groups and Generated ClusterRoleBindings ===${NC}"

# Function to detect if we're on OpenShift
detect_platform() {
    if command -v oc &> /dev/null && oc api-resources | grep -q "user.openshift.io"; then
        echo "openshift"
    else
        echo "kubernetes"
    fi
}

# Function to remove generated ClusterRoleBindings
cleanup_clusterrolebindings() {
    echo -e "${BLUE}=== Cleaning up Generated ClusterRoleBindings ===${NC}"
    
    # Find and delete ClusterRoleBindings managed by Kyverno
    echo -e "${YELLOW}Searching for Kyverno-managed ClusterRoleBindings...${NC}"
    
    # Get ClusterRoleBindings with Kyverno management labels
    local clusterrolebindings
    clusterrolebindings=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno -o name 2>/dev/null || true)
    
    if [[ -n "$clusterrolebindings" ]]; then
        echo "$clusterrolebindings" | while read -r crb; do
            if [[ -n "$crb" ]]; then
                local crb_name=${crb#clusterrolebinding.rbac.authorization.k8s.io/}
                echo -e "${YELLOW}Deleting ClusterRoleBinding: $crb_name${NC}"
                kubectl delete clusterrolebinding "$crb_name" --ignore-not-found=true
                echo -e "${GREEN}✓ Deleted ClusterRoleBinding: $crb_name${NC}"
            fi
        done
    else
        echo -e "${GREEN}✓ No Kyverno-managed ClusterRoleBindings found${NC}"
    fi
    
    # Also look for ClusterRoleBindings that match our naming pattern
    echo -e "${YELLOW}Searching for ClusterRoleBindings matching app-ocp-rbac pattern...${NC}"
    local pattern_crbs
    pattern_crbs=$(kubectl get clusterrolebindings -o name 2>/dev/null | grep "app-ocp-rbac.*-cluster-.*-\(admin\|edit\|view\)-crb" || true)
    
    if [[ -n "$pattern_crbs" ]]; then
        echo "$pattern_crbs" | while read -r crb; do
            if [[ -n "$crb" ]]; then
                local crb_name=${crb#clusterrolebinding.rbac.authorization.k8s.io/}
                echo -e "${YELLOW}Deleting pattern-matched ClusterRoleBinding: $crb_name${NC}"
                kubectl delete clusterrolebinding "$crb_name" --ignore-not-found=true
                echo -e "${GREEN}✓ Deleted ClusterRoleBinding: $crb_name${NC}"
            fi
        done
    else
        echo -e "${GREEN}✓ No pattern-matched ClusterRoleBindings found${NC}"
    fi
    
    echo ""
}

# Function to remove test groups
cleanup_groups() {
    echo -e "${BLUE}=== Removing Test Groups ===${NC}"
    
    # Get all groups with our test label
    local test_groups
    test_groups=$(kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test -o name 2>/dev/null || true)
    
    if [[ -n "$test_groups" ]]; then
        echo "$test_groups" | while read -r group; do
            if [[ -n "$group" ]]; then
                local group_name=${group#group.user.openshift.io/}
                echo -e "${YELLOW}Deleting Group: $group_name${NC}"
                
                # Show group members before deletion (if any)
                if [[ $PLATFORM == "openshift" ]] && command -v oc &> /dev/null; then
                    local users
                    users=$(oc get group "$group_name" -o jsonpath='{.users[*]}' 2>/dev/null || echo "none")
                    echo -e "${BLUE}  Users in group: $users${NC}"
                fi
                
                # Delete the group
                kubectl delete group "$group_name" --ignore-not-found=true
                echo -e "${GREEN}✓ Deleted Group: $group_name${NC}"
            fi
        done
    else
        echo -e "${GREEN}✓ No kyverno-test groups found${NC}"
    fi
    
    # Also look for groups that match our naming pattern (in case labels are missing)
    echo ""
    echo -e "${YELLOW}Searching for groups matching app-ocp-rbac pattern...${NC}"
    local pattern_groups
    pattern_groups=$(kubectl get groups -o name 2>/dev/null | grep "app-ocp-rbac" || true)
    
    if [[ -n "$pattern_groups" ]]; then
        echo -e "${YELLOW}Found pattern-matched groups:${NC}"
        echo "$pattern_groups" | while read -r group; do
            if [[ -n "$group" ]]; then
                local group_name=${group#group.user.openshift.io/}
                echo -e "${BLUE}  - $group_name${NC}"
            fi
        done
        
        echo ""
        echo -e "${YELLOW}Do you want to delete these pattern-matched groups? (y/N): ${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "$pattern_groups" | while read -r group; do
                if [[ -n "$group" ]]; then
                    local group_name=${group#group.user.openshift.io/}
                    echo -e "${YELLOW}Deleting pattern-matched Group: $group_name${NC}"
                    kubectl delete group "$group_name" --ignore-not-found=true
                    echo -e "${GREEN}✓ Deleted Group: $group_name${NC}"
                fi
            done
        else
            echo -e "${BLUE}Skipped pattern-matched groups${NC}"
        fi
    else
        echo -e "${GREEN}✓ No pattern-matched groups found${NC}"
    fi
    
    echo ""
}

# Function to clean up any orphaned resources
cleanup_orphaned_resources() {
    echo -e "${BLUE}=== Cleaning up Orphaned RBAC Resources ===${NC}"
    
    # Look for any remaining ClusterRoleBindings that reference non-existent groups
    echo -e "${YELLOW}Checking for orphaned ClusterRoleBindings...${NC}"
    
    # Get all ClusterRoleBindings that reference Groups
    local group_crbs
    group_crbs=$(kubectl get clusterrolebindings -o json 2>/dev/null | \
        jq -r '.items[] | select(.subjects[]?.kind == "Group") | select(.subjects[].name | startswith("app-ocp-rbac")) | .metadata.name' 2>/dev/null || true)
    
    if [[ -n "$group_crbs" ]]; then
        echo "$group_crbs" | while read -r crb_name; do
            if [[ -n "$crb_name" ]]; then
                # Check if the referenced group still exists
                local group_name
                group_name=$(kubectl get clusterrolebinding "$crb_name" -o json 2>/dev/null | \
                    jq -r '.subjects[]? | select(.kind == "Group") | .name' 2>/dev/null || true)
                
                if [[ -n "$group_name" ]] && ! kubectl get group "$group_name" >/dev/null 2>&1; then
                    echo -e "${YELLOW}Found orphaned ClusterRoleBinding: $crb_name (references non-existent group: $group_name)${NC}"
                    kubectl delete clusterrolebinding "$crb_name" --ignore-not-found=true
                    echo -e "${GREEN}✓ Deleted orphaned ClusterRoleBinding: $crb_name${NC}"
                fi
            fi
        done
    else
        echo -e "${GREEN}✓ No orphaned ClusterRoleBindings found${NC}"
    fi
    
    echo ""
}

# Function to verify cleanup
verify_cleanup() {
    echo -e "${BLUE}=== Verifying Cleanup ===${NC}"
    
    # Check for remaining test groups
    echo -e "${YELLOW}Checking for remaining test groups:${NC}"
    local remaining_groups
    remaining_groups=$(kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_groups" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $remaining_groups remaining test groups${NC}"
        kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null || true
    else
        echo -e "${GREEN}✓ No remaining test groups found${NC}"
    fi
    
    # Check for remaining Kyverno-managed ClusterRoleBindings
    echo ""
    echo -e "${YELLOW}Checking for remaining Kyverno-managed ClusterRoleBindings:${NC}"
    local remaining_crb
    remaining_crb=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_crb" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $remaining_crb remaining Kyverno-managed ClusterRoleBindings${NC}"
        kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null || true
    else
        echo -e "${GREEN}✓ No remaining Kyverno-managed ClusterRoleBindings found${NC}"
    fi
    
    # Check for app-ocp-rbac pattern ClusterRoleBindings
    echo ""
    echo -e "${YELLOW}Checking for app-ocp-rbac pattern ClusterRoleBindings:${NC}"
    local pattern_crbs
    pattern_crbs=$(kubectl get clusterrolebindings -o name 2>/dev/null | grep -c "app-ocp-rbac" || echo "0")
    if [[ "$pattern_crbs" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $pattern_crbs ClusterRoleBindings with app-ocp-rbac pattern${NC}"
        kubectl get clusterrolebindings -o name 2>/dev/null | grep "app-ocp-rbac" || true
    else
        echo -e "${GREEN}✓ No app-ocp-rbac pattern ClusterRoleBindings found${NC}"
    fi
    
    echo ""
}

# Function to show what cleanup will do
show_cleanup_plan() {
    echo -e "${BLUE}=== Cleanup Plan ===${NC}"
    echo -e "${YELLOW}This script will:${NC}"
    echo "1. Remove generated ClusterRoleBindings managed by Kyverno"
    echo "2. Delete test OpenShift Groups (labeled with kyverno-test)"
    echo "3. Optionally delete groups matching app-ocp-rbac pattern"
    echo "4. Clean up orphaned RBAC resources"
    echo "5. Verify cleanup completion"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete Groups and ClusterRoleBindings!${NC}"
    echo -e "${YELLOW}Users in deleted groups will lose their cluster access!${NC}"
    echo ""
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "${FORCE_CLEANUP:-}" == "true" ]]; then
        return 0
    fi
    
    read -p "Do you want to proceed with group cleanup? (y/N): " -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleanup cancelled${NC}"
        exit 0
    fi
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
    
    # Show cleanup plan
    show_cleanup_plan
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup steps
    cleanup_clusterrolebindings
    cleanup_groups
    cleanup_orphaned_resources
    verify_cleanup
    
    echo -e "${GREEN}=== Group cleanup completed! ===${NC}"
    echo -e "${YELLOW}Note: Namespace cleanup should be run separately${NC}"
    echo "Run './scripts/cleanup-namespaces.sh' to clean up test namespaces"
}

# Handle command line arguments
if [[ "$1" == "--force" ]]; then
    export FORCE_CLEANUP=true
fi

# Run main function
main "$@"
