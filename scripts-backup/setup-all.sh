#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Kyverno RBAC Test Environment Complete Setup ===${NC}"
echo -e "${YELLOW}This script will set up the complete test environment for Kyverno RBAC policies${NC}"
echo ""

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
KYVERNO_NAMESPACE="kyverno"

# Functions for each setup phase
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
    
    # Check if Kyverno is installed
    if kubectl get namespace "$KYVERNO_NAMESPACE" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Kyverno namespace exists${NC}"
    else
        echo -e "${YELLOW}⚠ Kyverno namespace not found${NC}"
        echo -e "${YELLOW}  Install Kyverno first: helm install kyverno kyverno/kyverno -n kyverno --create-namespace${NC}"
    fi
    
    # Check for YAML policy files
    local yaml_count
    yaml_count=$(find "$PROJECT_ROOT" -maxdepth 1 -name "*.yaml" | wc -l)
    if [[ $yaml_count -ge 5 ]]; then
        echo -e "${GREEN}✓ Found $yaml_count YAML policy files${NC}"
    else
        echo -e "${YELLOW}⚠ Expected at least 5 YAML files, found $yaml_count${NC}"
    fi
    
    echo ""
}

show_setup_plan() {
    echo -e "${BLUE}=== Setup Plan ===${NC}"
    echo -e "${YELLOW}This will perform the following steps:${NC}"
    echo "1. Apply Kyverno RBAC policies and permissions"
    echo "2. Create test namespaces with proper labels"
    echo "3. Create OpenShift Groups for testing"
    echo "4. Wait for Kyverno to generate RBAC resources"
    echo "5. Verify the complete setup"
    echo ""
    echo -e "${YELLOW}Test Resources to be Created:${NC}"
    echo "• Namespaces: demo-ns, team-alpha-dev, team-beta-prod, shared-tools, kill-switch-test"
    echo "• OpenShift Groups: ~18 groups (namespace + cluster scoped)"
    echo "• Generated RoleBindings: ~12+ per active namespace"
    echo "• Generated ClusterRoleBindings: ~8 cluster-wide bindings"
    echo ""
}

apply_kyverno_policies() {
    echo -e "${BLUE}=== Applying Kyverno RBAC Policies ===${NC}"
    
    # Apply policies in correct order
    local policy_files=(
        "$PROJECT_ROOT/kyverno-rbac-clusterrole.yaml"
        "$PROJECT_ROOT/kyverno-rbac-clusterrolebinding.yaml"
        "$PROJECT_ROOT/enforce-rbac-standards-policy.yaml"
        "$PROJECT_ROOT/generate-namespace-rolebindings-policy.yaml"
        "$PROJECT_ROOT/generate-cluster-rolebindings-policy.yaml"
    )
    
    for policy_file in "${policy_files[@]}"; do
        if [[ -f "$policy_file" ]]; then
            local filename=$(basename "$policy_file")
            echo -e "${YELLOW}Applying: $filename${NC}"
            kubectl apply -f "$policy_file"
            echo -e "${GREEN}✓ Applied: $filename${NC}"
        else
            echo -e "${RED}ERROR: Policy file not found: $policy_file${NC}"
            exit 1
        fi
    done
    
    # Wait for policies to be ready
    echo -e "${YELLOW}Waiting for policies to be ready...${NC}"
    sleep 5
    
    # Verify policies are installed
    echo -e "${YELLOW}Verifying policy installation:${NC}"
    kubectl get clusterpolicies
    
    echo ""
}

setup_test_environment() {
    echo -e "${BLUE}=== Setting up Test Environment ===${NC}"
    
    # Run namespace setup
    echo -e "${YELLOW}Running namespace setup...${NC}"
    if [[ -x "$SCRIPT_DIR/setup-namespaces.sh" ]]; then
        "$SCRIPT_DIR/setup-namespaces.sh"
    else
        echo -e "${RED}ERROR: setup-namespaces.sh not found or not executable${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Waiting for namespace processing...${NC}"
    sleep 3
    
    # Run group setup
    echo -e "${YELLOW}Running group setup...${NC}"
    if [[ -x "$SCRIPT_DIR/setup-groups.sh" ]]; then
        "$SCRIPT_DIR/setup-groups.sh"
    else
        echo -e "${RED}ERROR: setup-groups.sh not found or not executable${NC}"
        exit 1
    fi
    
    echo ""
}

wait_for_generation() {
    echo -e "${BLUE}=== Waiting for Kyverno Resource Generation ===${NC}"
    echo -e "${YELLOW}Kyverno needs time to process and generate RBAC resources...${NC}"
    
    # Wait with progress indicator
    local wait_time=60
    for ((i=wait_time; i>0; i--)); do
        echo -ne "${YELLOW}\rWaiting... ${i}s remaining${NC}"
        sleep 1
    done
    echo ""
    
    echo -e "${GREEN}✓ Wait completed${NC}"
    echo ""
}

verify_setup() {
    echo -e "${BLUE}=== Verifying Complete Setup ===${NC}"
    
    # Check Kyverno policies
    echo -e "${YELLOW}Kyverno ClusterPolicies:${NC}"
    kubectl get clusterpolicies --no-headers | wc -l | xargs echo -e "${GREEN}Total policies installed:${NC}"
    
    # Check test namespaces
    echo -e "${YELLOW}Test Namespaces:${NC}"
    kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --no-headers | wc -l | xargs echo -e "${GREEN}Test namespaces created:${NC}"
    
    # Check OpenShift groups
    echo -e "${YELLOW}OpenShift Groups:${NC}"
    kubectl get groups -l app.kubernetes.io/managed-by=kyverno-test --no-headers 2>/dev/null | wc -l | xargs echo -e "${GREEN}Test groups created:${NC}" || echo -e "${YELLOW}Groups check skipped (not OpenShift?)${NC}"
    
    # Check generated RoleBindings
    echo -e "${YELLOW}Generated RoleBindings:${NC}"
    kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l | xargs echo -e "${GREEN}Generated RoleBindings:${NC}" || echo "0"
    
    # Check generated ClusterRoleBindings
    echo -e "${YELLOW}Generated ClusterRoleBindings:${NC}"
    kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l | xargs echo -e "${GREEN}Generated ClusterRoleBindings:${NC}" || echo "0"
    
    echo ""
}

show_test_commands() {
    echo -e "${BLUE}=== Test Environment Ready! ===${NC}"
    echo -e "${YELLOW}Test Commands:${NC}"
    echo ""
    echo -e "${GREEN}1. View generated RoleBindings:${NC}"
    echo "   kubectl get rolebindings -n demo-ns"
    echo "   kubectl get rolebindings -n team-alpha-dev"
    echo ""
    echo -e "${GREEN}2. View generated ClusterRoleBindings:${NC}"
    echo "   kubectl get clusterrolebindings | grep kyverno"
    echo "   kubectl get clusterrolebindings | grep app-ocp-rbac"
    echo ""
    echo -e "${GREEN}3. Test kill-switch (should have no RoleBindings):${NC}"
    echo "   kubectl get rolebindings -n kill-switch-test"
    echo ""
    echo -e "${GREEN}4. View policy violations (should be empty in Audit mode):${NC}"
    echo "   kubectl get events --field-selector reason=PolicyViolation"
    echo ""
    echo -e "${GREEN}5. Test label changes:${NC}"
    echo "   kubectl label ns demo-ns oim-ns-edit- # Remove edit label"
    echo "   # Wait a few minutes, then check if edit RoleBinding is removed"
    echo ""
    echo -e "${YELLOW}Cleanup:${NC}"
    echo "   ./scripts/cleanup-all.sh    # Clean up everything"
    echo "   ./scripts/cleanup-all.sh --force    # Clean up without prompts"
}

confirm_setup() {
    if [[ "${SKIP_CONFIRM:-}" == "true" ]]; then
        return 0
    fi
    
    read -p "Do you want to proceed with the complete setup? (y/N): " -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Setup cancelled${NC}"
        exit 0
    fi
}

# Main execution
main() {
    echo -e "${GREEN}Project root: $PROJECT_ROOT${NC}"
    echo -e "${GREEN}Script directory: $SCRIPT_DIR${NC}"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Show plan
    show_setup_plan
    
    # Confirm setup
    confirm_setup
    
    # Execute setup phases
    apply_kyverno_policies
    setup_test_environment
    wait_for_generation
    verify_setup
    show_test_commands
    
    echo -e "${GREEN}=== Complete setup finished successfully! ===${NC}"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirm)
            export SKIP_CONFIRM=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --skip-confirm    Skip confirmation prompts"
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
