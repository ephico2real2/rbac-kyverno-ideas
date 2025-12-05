#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cleaning up Test Namespaces and Generated RBAC Resources (v2-numbered) ===${NC}"

# Test namespaces to remove
TEST_NAMESPACES=(
    "demo-ns"
    "team-alpha-dev"
    "team-beta-prod"
    "shared-tools"
    "multi-admin-test"
    "kill-switch-test"
)

# System namespaces to reset (remove test labels)
SYSTEM_NAMESPACES=(
    "openshift-config"
    "kube-system"
    "kube-public"
)

# Function to remove generated RoleBindings
cleanup_rolebindings() {
    echo -e "${BLUE}=== Cleaning up Generated RoleBindings ===${NC}"
    
    # Find and delete RoleBindings managed by Kyverno
    echo -e "${YELLOW}Searching for Kyverno-managed RoleBindings...${NC}"
    
    # Get all RoleBindings with Kyverno management labels
    local rolebindings
    rolebindings=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    
    if [[ -n "$rolebindings" ]]; then
        echo "$rolebindings" | while read -r namespace name; do
            if [[ -n "$namespace" && -n "$name" ]]; then
                echo -e "${YELLOW}Deleting RoleBinding: $namespace/$name${NC}"
                kubectl delete rolebinding "$name" -n "$namespace" --ignore-not-found=true
                echo -e "${GREEN}✓ Deleted RoleBinding: $namespace/$name${NC}"
            fi
        done
    else
        echo -e "${GREEN}✓ No Kyverno-managed RoleBindings found${NC}"
    fi
    
    echo ""
}

# Function to remove test namespaces
cleanup_namespaces() {
    echo -e "${BLUE}=== Removing Test Namespaces ===${NC}"
    
    for ns in "${TEST_NAMESPACES[@]}"; do
        echo -e "${YELLOW}Processing namespace: $ns${NC}"
        
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            # Show what will be deleted
            echo -e "${YELLOW}Namespace '$ns' contains:${NC}"
            kubectl get all -n "$ns" --no-headers 2>/dev/null | head -5 || echo "  (no resources or access denied)"
            
            # Delete the namespace (this will cascade delete all resources)
            echo -e "${YELLOW}Deleting namespace '$ns'...${NC}"
            kubectl delete namespace "$ns" --ignore-not-found=true
            echo -e "${GREEN}✓ Namespace '$ns' deleted${NC}"
        else
            echo -e "${GREEN}✓ Namespace '$ns' does not exist${NC}"
        fi
        echo ""
    done
}

# Function to reset system namespaces (remove test labels)
reset_system_namespaces() {
    echo -e "${BLUE}=== Resetting System Namespaces ===${NC}"
    
    for ns in "${SYSTEM_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            echo -e "${YELLOW}Resetting labels on system namespace: $ns${NC}"
            
            # Remove v1 test labels (single labels)
            kubectl label namespace "$ns" kyverno.io/exclude-rbac- --ignore-not-found=true 2>/dev/null || true
            kubectl label namespace "$ns" oim-ns-admin- --ignore-not-found=true 2>/dev/null || true
            kubectl label namespace "$ns" oim-ns-edit- --ignore-not-found=true 2>/dev/null || true
            kubectl label namespace "$ns" oim-ns-view- --ignore-not-found=true 2>/dev/null || true
            kubectl label namespace "$ns" app.kubernetes.io/managed-by- --ignore-not-found=true 2>/dev/null || true
            
            # Remove v2 numbered test labels (oim-ns-admin-1, oim-ns-admin-2, etc.)
            # Get all labels and filter for numbered ones
            local labels
            labels=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels}' 2>/dev/null || echo '{}')
            
            # Remove numbered admin labels
            for i in {1..10}; do
                kubectl label namespace "$ns" "oim-ns-admin-${i}-" --ignore-not-found=true 2>/dev/null || true
                kubectl label namespace "$ns" "oim-ns-edit-${i}-" --ignore-not-found=true 2>/dev/null || true
                kubectl label namespace "$ns" "oim-ns-view-${i}-" --ignore-not-found=true 2>/dev/null || true
            done
            
            echo -e "${GREEN}✓ Reset labels on namespace '$ns'${NC}"
        else
            echo -e "${YELLOW}⚠ System namespace '$ns' not found (not OpenShift cluster?)${NC}"
        fi
    done
    
    echo ""
}

# Function to clean up any remaining test-related resources
cleanup_remaining_resources() {
    echo -e "${BLUE}=== Cleaning up Remaining Test Resources ===${NC}"
    
    # Look for any resources with our test labels
    echo -e "${YELLOW}Searching for resources with kyverno-test labels...${NC}"
    
    # Clean up any ConfigMaps, Secrets, etc. with test labels
    kubectl get configmaps -A -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | \
        while read -r namespace name rest; do
            if [[ -n "$namespace" && -n "$name" ]]; then
                echo -e "${YELLOW}Deleting ConfigMap: $namespace/$name${NC}"
                kubectl delete configmap "$name" -n "$namespace" --ignore-not-found=true
            fi
        done || true
    
    kubectl get secrets -A -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | \
        while read -r namespace name rest; do
            if [[ -n "$namespace" && -n "$name" ]]; then
                echo -e "${YELLOW}Deleting Secret: $namespace/$name${NC}"
                kubectl delete secret "$name" -n "$namespace" --ignore-not-found=true
            fi
        done || true
    
    echo -e "${GREEN}✓ Cleaned up remaining test resources${NC}"
    echo ""
}

# Function to verify cleanup
verify_cleanup() {
    echo -e "${BLUE}=== Verifying Cleanup ===${NC}"
    
    echo -e "${YELLOW}Checking for remaining test namespaces:${NC}"
    for ns in "${TEST_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" >/dev/null 2>&1; then
            echo -e "${RED}✗ Namespace '$ns' still exists${NC}"
        else
            echo -e "${GREEN}✓ Namespace '$ns' removed${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}Checking for remaining Kyverno-managed RoleBindings:${NC}"
    local remaining_rb
    remaining_rb=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_rb" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $remaining_rb remaining Kyverno-managed RoleBindings${NC}"
        kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null || true
    else
        echo -e "${GREEN}✓ No remaining Kyverno-managed RoleBindings found${NC}"
    fi
    
    echo ""
}

# Function to show what cleanup will do
show_cleanup_plan() {
    echo -e "${BLUE}=== Cleanup Plan ===${NC}"
    echo -e "${YELLOW}This script will:${NC}"
    echo "1. Remove generated RoleBindings managed by Kyverno"
    echo "2. Delete test namespaces: ${TEST_NAMESPACES[*]}"
    echo "3. Reset labels on system namespaces: ${SYSTEM_NAMESPACES[*]} (both v1 and v2-numbered labels)"
    echo "4. Clean up any remaining test resources"
    echo "5. Verify cleanup completion"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete namespaces and their contents!${NC}"
    echo ""
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "${FORCE_CLEANUP:-}" == "true" ]]; then
        return 0
    fi
    
    read -p "Do you want to proceed with cleanup? (y/N): " -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleanup cancelled${NC}"
        exit 0
    fi
}

# Main execution
main() {
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
    cleanup_rolebindings
    cleanup_namespaces
    reset_system_namespaces
    cleanup_remaining_resources
    verify_cleanup
    
    echo -e "${GREEN}=== Namespace cleanup completed! ===${NC}"
    echo -e "${YELLOW}Note: OpenShift Groups and ClusterRoleBindings are cleaned up separately${NC}"
    echo "Run './scripts/cleanup-groups.sh' to clean up Groups and ClusterRoleBindings"
}

# Handle command line arguments
if [[ "$1" == "--force" ]]; then
    export FORCE_CLEANUP=true
fi

# Run main function
main "$@"
