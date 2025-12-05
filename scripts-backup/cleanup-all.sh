#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kyverno RBAC Test Environment Complete Cleanup ===${NC}"
echo -e "${YELLOW}This script will clean up the entire test environment${NC}"
echo ""

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FORCE_MODE=false

# Function to show cleanup plan
show_cleanup_plan() {
    echo -e "${BLUE}=== Complete Cleanup Plan ===${NC}"
    echo -e "${YELLOW}This will perform the following cleanup steps:${NC}"
    echo "1. Remove all generated RBAC resources (RoleBindings, ClusterRoleBindings)"
    echo "2. Delete test OpenShift Groups"
    echo "3. Remove test namespaces and their contents"
    echo "4. Reset system namespace labels"
    echo "5. Optionally remove Kyverno policies"
    echo "6. Clean up any remaining test resources"
    echo ""
    echo -e "${RED}WARNING: This will permanently delete:${NC}"
    echo -e "${RED}• All test namespaces and their workloads${NC}"
    echo -e "${RED}• All test OpenShift Groups (users will lose access)${NC}"
    echo -e "${RED}• All generated RBAC bindings${NC}"
    if [[ "${REMOVE_POLICIES:-}" == "true" ]]; then
        echo -e "${RED}• All Kyverno RBAC policies${NC}"
    fi
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}=== Checking Prerequisites ===${NC}"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}ERROR: kubectl is not installed${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ kubectl found${NC}"
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Connected to cluster: $(kubectl config current-context)${NC}"
    
    # Check for cleanup scripts
    if [[ ! -x "$SCRIPT_DIR/cleanup-groups.sh" ]]; then
        echo -e "${RED}ERROR: cleanup-groups.sh not found or not executable${NC}"
        exit 1
    fi
    
    if [[ ! -x "$SCRIPT_DIR/cleanup-namespaces.sh" ]]; then
        echo -e "${RED}ERROR: cleanup-namespaces.sh not found or not executable${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Cleanup scripts found${NC}"
    echo ""
}

# Function to show current test environment
show_current_environment() {
    echo -e "${BLUE}=== Current Test Environment ===${NC}"
    
    # Count resources
    local ns_count
    ns_count=$(kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l || echo "0")
    echo -e "${YELLOW}Test namespaces: $ns_count${NC}"
    
    local group_count
    group_count=$(kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l || echo "0")
    echo -e "${YELLOW}Test groups: $group_count${NC}"
    
    local rb_count
    rb_count=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l || echo "0")
    echo -e "${YELLOW}Generated RoleBindings: $rb_count${NC}"
    
    local crb_count
    crb_count=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l || echo "0")
    echo -e "${YELLOW}Generated ClusterRoleBindings: $crb_count${NC}"
    
    local policy_count
    policy_count=$(kubectl get clusterpolicies --no-headers 2>/dev/null | grep -E "(enforce-rbac|generate-)" | wc -l || echo "0")
    echo -e "${YELLOW}RBAC policies: $policy_count${NC}"
    
    # Show detailed breakdown if resources exist
    if [[ $ns_count -gt 0 ]]; then
        echo ""
        echo -e "${BLUE}Test namespaces to be deleted:${NC}"
        kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --no-headers | awk '{print "  • " $1}'
    fi
    
    if [[ $group_count -gt 0 ]]; then
        echo ""
        echo -e "${BLUE}Test groups to be deleted:${NC}"
        kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | awk '{print "  • " $1}' | head -10
        if [[ $group_count -gt 10 ]]; then
            echo "  • ... and $((group_count - 10)) more"
        fi
    fi
    
    echo ""
}

# Function to run cleanup phases
run_cleanup_phases() {
    echo -e "${BLUE}=== Executing Cleanup Phases ===${NC}"
    
    # Phase 1: Clean up groups and ClusterRoleBindings
    echo -e "${YELLOW}Phase 1: Cleaning up Groups and ClusterRoleBindings${NC}"
    if [[ $FORCE_MODE == true ]]; then
        FORCE_CLEANUP=true "$SCRIPT_DIR/cleanup-groups.sh" --force
    else
        "$SCRIPT_DIR/cleanup-groups.sh"
    fi
    echo ""
    
    # Phase 2: Clean up namespaces and RoleBindings
    echo -e "${YELLOW}Phase 2: Cleaning up Namespaces and RoleBindings${NC}"
    if [[ $FORCE_MODE == true ]]; then
        FORCE_CLEANUP=true "$SCRIPT_DIR/cleanup-namespaces.sh" --force
    else
        "$SCRIPT_DIR/cleanup-namespaces.sh"
    fi
    echo ""
    
    # Phase 3: Optionally remove Kyverno policies
    if [[ "${REMOVE_POLICIES:-}" == "true" ]]; then
        echo -e "${YELLOW}Phase 3: Removing Kyverno RBAC Policies${NC}"
        remove_kyverno_policies
        echo ""
    fi
}

# Function to remove Kyverno policies
remove_kyverno_policies() {
    echo -e "${BLUE}=== Removing Kyverno RBAC Policies ===${NC}"
    
    local policy_files=(
        "generate-cluster-rolebindings-policy.yaml"
        "generate-namespace-rolebindings-policy.yaml"
        "enforce-rbac-standards-policy.yaml"
        "kyverno-rbac-clusterrolebinding.yaml"
        "kyverno-rbac-clusterrole.yaml"
    )
    
    for policy_file in "${policy_files[@]}"; do
        local full_path="$PROJECT_ROOT/$policy_file"
        if [[ -f "$full_path" ]]; then
            echo -e "${YELLOW}Removing: $policy_file${NC}"
            kubectl delete -f "$full_path" --ignore-not-found=true
            echo -e "${GREEN}✓ Removed: $policy_file${NC}"
        else
            echo -e "${YELLOW}⚠ Policy file not found: $policy_file${NC}"
        fi
    done
    
    # Also remove by name in case files are missing
    echo -e "${YELLOW}Removing policies by name...${NC}"
    kubectl delete clusterpolicy generate-cluster-rolebindings --ignore-not-found=true
    kubectl delete clusterpolicy generate-namespace-rolebindings --ignore-not-found=true
    kubectl delete clusterpolicy enforce-rbac-ns-standards --ignore-not-found=true
    kubectl delete clusterrolebinding kyverno-admin-generate --ignore-not-found=true
    kubectl delete clusterrole kyverno:rbac-generatecontroller --ignore-not-found=true
}

# Function to clean up any remaining test resources
cleanup_remaining_resources() {
    echo -e "${BLUE}=== Final Cleanup of Remaining Resources ===${NC}"
    
    # Look for any remaining test-labeled resources
    echo -e "${YELLOW}Searching for remaining test resources...${NC}"
    
    # Clean up any remaining ClusterRoleBindings with our patterns
    local remaining_crbs
    remaining_crbs=$(kubectl get clusterrolebindings -o name 2>/dev/null | grep "app-ocp-rbac" || true)
    if [[ -n "$remaining_crbs" ]]; then
        echo -e "${YELLOW}Found remaining ClusterRoleBindings with app-ocp-rbac pattern:${NC}"
        echo "$remaining_crbs" | while read -r crb; do
            local crb_name=${crb#clusterrolebinding.rbac.authorization.k8s.io/}
            echo -e "${YELLOW}  Deleting: $crb_name${NC}"
            kubectl delete clusterrolebinding "$crb_name" --ignore-not-found=true
        done
    fi
    
    # Clean up any remaining Groups with our patterns
    local remaining_groups
    remaining_groups=$(kubectl get groups -o name 2>/dev/null | grep "app-ocp-rbac" || true)
    if [[ -n "$remaining_groups" ]]; then
        echo -e "${YELLOW}Found remaining Groups with app-ocp-rbac pattern:${NC}"
        echo "$remaining_groups" | while read -r group; do
            local group_name=${group#group.user.openshift.io/}
            echo -e "${YELLOW}  Deleting: $group_name${NC}"
            kubectl delete group "$group_name" --ignore-not-found=true
        done
    fi
    
    echo -e "${GREEN}✓ Final cleanup completed${NC}"
    echo ""
}

# Function to verify complete cleanup
verify_complete_cleanup() {
    echo -e "${BLUE}=== Verifying Complete Cleanup ===${NC}"
    
    # Check each resource type
    local issues=0
    
    # Test namespaces
    local remaining_ns
    remaining_ns=$(kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_ns" -gt 0 ]]; then
        echo -e "${RED}✗ Found $remaining_ns remaining test namespaces${NC}"
        ((issues++))
    else
        echo -e "${GREEN}✓ No remaining test namespaces${NC}"
    fi
    
    # Test groups
    local remaining_groups
    remaining_groups=$(kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_groups" -gt 0 ]]; then
        echo -e "${RED}✗ Found $remaining_groups remaining test groups${NC}"
        ((issues++))
    else
        echo -e "${GREEN}✓ No remaining test groups${NC}"
    fi
    
    # Generated RoleBindings
    local remaining_rb
    remaining_rb=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_rb" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $remaining_rb remaining Kyverno-managed RoleBindings${NC}"
    else
        echo -e "${GREEN}✓ No remaining Kyverno-managed RoleBindings${NC}"
    fi
    
    # Generated ClusterRoleBindings
    local remaining_crb
    remaining_crb=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ "$remaining_crb" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ Found $remaining_crb remaining Kyverno-managed ClusterRoleBindings${NC}"
    else
        echo -e "${GREEN}✓ No remaining Kyverno-managed ClusterRoleBindings${NC}"
    fi
    
    # RBAC policies (if removal was requested)
    if [[ "${REMOVE_POLICIES:-}" == "true" ]]; then
        local remaining_policies
        remaining_policies=$(kubectl get clusterpolicies --no-headers 2>/dev/null | grep -E "(enforce-rbac|generate-)" | wc -l || echo "0")
        if [[ "$remaining_policies" -gt 0 ]]; then
            echo -e "${RED}✗ Found $remaining_policies remaining RBAC policies${NC}"
            ((issues++))
        else
            echo -e "${GREEN}✓ No remaining RBAC policies${NC}"
        fi
    fi
    
    echo ""
    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✅ Cleanup completed successfully with no issues!${NC}"
    else
        echo -e "${YELLOW}⚠ Cleanup completed with $issues issues that may need manual attention${NC}"
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ $FORCE_MODE == true ]]; then
        return 0
    fi
    
    read -p "Do you want to proceed with complete cleanup? (y/N): " -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Cleanup cancelled${NC}"
        exit 0
    fi
    
    # Ask about policy removal if not specified
    if [[ -z "${REMOVE_POLICIES:-}" ]]; then
        echo ""
        read -p "Do you also want to remove Kyverno RBAC policies? (y/N): " -r policy_response
        if [[ "$policy_response" =~ ^[Yy]$ ]]; then
            export REMOVE_POLICIES=true
        fi
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Script directory: $SCRIPT_DIR${NC}"
    echo -e "${GREEN}Project root: $PROJECT_ROOT${NC}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Show current environment
    show_current_environment
    
    # Show cleanup plan
    show_cleanup_plan
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup phases
    run_cleanup_phases
    
    # Final cleanup
    cleanup_remaining_resources
    
    # Verify cleanup
    verify_complete_cleanup
    
    echo -e "${GREEN}=== Complete cleanup finished! ===${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "• Your cluster is now cleaned of all test resources"
    if [[ "${REMOVE_POLICIES:-}" != "true" ]]; then
        echo "• Kyverno RBAC policies are still installed (remove with --remove-policies if desired)"
    fi
    echo "• You can re-run the test setup with: ./scripts/setup-all.sh"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_MODE=true
            shift
            ;;
        --remove-policies)
            export REMOVE_POLICIES=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force           Skip confirmation prompts"
            echo "  --remove-policies Remove Kyverno RBAC policies in addition to test resources"
            echo "  --help, -h        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
