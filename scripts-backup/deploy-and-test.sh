#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
VERSION=${1:-"v2"}  # Default to v2-numbered
WAIT_TIME=30        # Time to wait for Kyverno to process policies

echo -e "${BLUE}=== Kyverno RBAC Policy Deployment and Testing ===${NC}"
echo -e "${YELLOW}Version: $VERSION${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}=== Checking Prerequisites ===${NC}"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}ERROR: kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ kubectl available${NC}"
    echo -e "${GREEN}✓ Connected to cluster: $(kubectl config current-context)${NC}"
    
    # Check if Kyverno is installed
    if ! kubectl get deploy kyverno -n kyverno >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Kyverno is not installed in the cluster${NC}"
        echo -e "${YELLOW}Please install Kyverno first:${NC}"
        echo "  helm repo add kyverno https://kyverno.github.io/kyverno/"
        echo "  helm repo update"
        echo "  helm install kyverno kyverno/kyverno -n kyverno --create-namespace"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Kyverno is installed${NC}"
    echo ""
}

# Function to cleanup previous test environment
cleanup_environment() {
    echo -e "${BLUE}=== Cleaning up Previous Test Environment ===${NC}"
    
    if [[ "$VERSION" == "v1" ]]; then
        if [[ -f "$SCRIPT_DIR/cleanup-namespaces-v1.sh" ]]; then
            echo -e "${YELLOW}Running v1 cleanup script...${NC}"
            bash "$SCRIPT_DIR/cleanup-namespaces-v1.sh" --force
        fi
    else
        if [[ -f "$SCRIPT_DIR/cleanup-namespaces-v2-numbered.sh" ]]; then
            echo -e "${YELLOW}Running v2-numbered cleanup script...${NC}"
            bash "$SCRIPT_DIR/cleanup-namespaces-v2-numbered.sh" --force
        fi
    fi
    
    # Remove any existing policies
    kubectl delete clusterpolicy generate-ns-rolebindings --ignore-not-found=true
    kubectl delete clusterpolicy generate-ns-rolebindings-v2-numbered --ignore-not-found=true
    kubectl delete clusterpolicy generate-namespace-rolebindings --ignore-not-found=true
    kubectl delete clusterpolicy enforce-rbac-ns-standards --ignore-not-found=true
    kubectl delete clusterpolicy enforce-rbac-ns-standards-v2-numbered --ignore-not-found=true
    
    echo -e "${GREEN}✓ Environment cleaned up${NC}"
    echo ""
}

# Function to deploy the policy
deploy_policy() {
    echo -e "${BLUE}=== Deploying Kyverno Policy ===${NC}"
    
    if [[ "$VERSION" == "v1" ]]; then
        local policy_file="$PROJECT_ROOT/namespace-rolebinding-policy-v1.yaml"
        if [[ -f "$policy_file" ]]; then
            echo -e "${YELLOW}Deploying v1 policy...${NC}"
            kubectl apply -f "$policy_file"
            echo -e "${GREEN}✓ v1 policy deployed${NC}"
        else
            echo -e "${RED}ERROR: v1 policy file not found: $policy_file${NC}"
            exit 1
        fi
    else
        # Deploy v2-numbered generate policy
        local generate_policy_file="$PROJECT_ROOT/generate-namespace-rolebindings-policy-v2-numbered.yaml"
        if [[ -f "$generate_policy_file" ]]; then
            echo -e "${YELLOW}Deploying v2-numbered generate policy...${NC}"
            kubectl apply -f "$generate_policy_file"
            echo -e "${GREEN}✓ v2-numbered generate policy deployed${NC}"
        else
            echo -e "${RED}ERROR: v2-numbered generate policy file not found: $generate_policy_file${NC}"
            exit 1
        fi
        
        # Deploy v2-numbered validation policy
        local validate_policy_file="$PROJECT_ROOT/enforce-rbac-standards-policy-v2-numbered.yaml"
        if [[ -f "$validate_policy_file" ]]; then
            echo -e "${YELLOW}Deploying v2-numbered validation policy...${NC}"
            kubectl apply -f "$validate_policy_file"
            echo -e "${GREEN}✓ v2-numbered validation policy deployed${NC}"
        else
            echo -e "${YELLOW}Warning: v2-numbered validation policy file not found: $validate_policy_file${NC}"
        fi
    fi
    echo ""
}

# Function to setup test namespaces
setup_namespaces() {
    echo -e "${BLUE}=== Setting up Test Namespaces ===${NC}"
    
    if [[ "$VERSION" == "v1" ]]; then
        if [[ -f "$SCRIPT_DIR/setup-namespaces-v1.sh" ]]; then
            echo -e "${YELLOW}Running v1 namespace setup...${NC}"
            bash "$SCRIPT_DIR/setup-namespaces-v1.sh"
        else
            echo -e "${RED}ERROR: v1 namespace setup script not found${NC}"
            exit 1
        fi
    else
        if [[ -f "$SCRIPT_DIR/setup-namespaces-v2-numbered.sh" ]]; then
            echo -e "${YELLOW}Running v2-numbered namespace setup...${NC}"
            bash "$SCRIPT_DIR/setup-namespaces-v2-numbered.sh"
        else
            echo -e "${RED}ERROR: v2-numbered namespace setup script not found${NC}"
            exit 1
        fi
    fi
    echo ""
}

# Function to wait for Kyverno to process policies
wait_for_processing() {
    echo -e "${BLUE}=== Waiting for Kyverno to Process Policies ===${NC}"
    echo -e "${YELLOW}Waiting ${WAIT_TIME} seconds for RoleBinding generation...${NC}"
    
    for ((i=1; i<=WAIT_TIME; i++)); do
        printf "."
        sleep 1
        if ((i % 10 == 0)); then
            printf " ${i}s\n"
        fi
    done
    echo ""
    echo -e "${GREEN}✓ Wait period completed${NC}"
    echo ""
}

# Function to verify results
verify_results() {
    echo -e "${BLUE}=== Verifying Results ===${NC}"
    
    # Check generated RoleBindings
    echo -e "${YELLOW}Checking generated RoleBindings:${NC}"
    local rolebindings
    rolebindings=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null || echo "")
    
    if [[ -n "$rolebindings" ]]; then
        echo "$rolebindings" | while read -r namespace name type data age; do
            echo -e "${GREEN}✓ Found RoleBinding: $namespace/$name${NC}"
        done
        
        echo ""
        echo -e "${YELLOW}Detailed RoleBinding information:${NC}"
        kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno -o wide
        
        echo ""
        echo -e "${YELLOW}Sample RoleBinding details:${NC}"
        local first_rb_ns first_rb_name
        first_rb_ns=$(echo "$rolebindings" | head -1 | awk '{print $1}')
        first_rb_name=$(echo "$rolebindings" | head -1 | awk '{print $2}')
        if [[ -n "$first_rb_ns" && -n "$first_rb_name" ]]; then
            kubectl describe rolebinding "$first_rb_name" -n "$first_rb_ns"
        fi
    else
        echo -e "${RED}✗ No RoleBindings found managed by Kyverno${NC}"
        echo -e "${YELLOW}Checking Kyverno logs for errors:${NC}"
        kubectl logs -n kyverno deployment/kyverno --tail=20 || true
    fi
    
    echo ""
    echo -e "${YELLOW}Test namespaces:${NC}"
    kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --show-labels
    
    echo ""
}

# Function to show policy status
show_policy_status() {
    echo -e "${BLUE}=== Policy Status ===${NC}"
    
    if [[ "$VERSION" == "v1" ]]; then
        echo -e "${YELLOW}Generate Policy:${NC}"
        kubectl get clusterpolicy generate-ns-rolebindings -o wide 2>/dev/null || echo "v1 generate policy not found"
        echo ""
        echo -e "${YELLOW}Validation Policy:${NC}"
        kubectl get clusterpolicy enforce-rbac-ns-standards -o wide 2>/dev/null || echo "v1 validation policy not found"
    else
        echo -e "${YELLOW}Generate Policy:${NC}"
        kubectl get clusterpolicy generate-namespace-rolebindings -o wide 2>/dev/null || echo "v2-numbered generate policy not found"
        echo ""
        echo -e "${YELLOW}Validation Policy:${NC}"
        kubectl get clusterpolicy enforce-rbac-ns-standards-v2-numbered -o wide 2>/dev/null || echo "v2-numbered validation policy not found"
    fi
    
    echo ""
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [v1|v2]"
    echo ""
    echo "Options:"
    echo "  v1  - Deploy and test the v1 policy (comma-separated labels)"
    echo "  v2  - Deploy and test the v2-numbered policy (numbered labels) [DEFAULT]"
    echo ""
    echo "Examples:"
    echo "  $0 v1   # Test v1 policy"
    echo "  $0 v2   # Test v2-numbered policy"
    echo "  $0      # Test v2-numbered policy (default)"
}

# Main execution
main() {
    # Check version argument
    if [[ "$VERSION" != "v1" && "$VERSION" != "v2" ]]; then
        echo -e "${RED}ERROR: Invalid version '$VERSION'. Must be 'v1' or 'v2'${NC}"
        show_usage
        exit 1
    fi
    
    # Execute deployment and testing steps
    check_prerequisites
    cleanup_environment
    deploy_policy
    setup_namespaces
    wait_for_processing
    verify_results
    show_policy_status
    
    echo -e "${GREEN}=== Deployment and Testing Completed! ===${NC}"
    echo -e "${YELLOW}Summary:${NC}"
    echo "- Version: $VERSION"
    echo "- Policy deployed and namespaces configured"
    echo "- Check the verification results above"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Review the generated RoleBindings"
    echo "2. Test RBAC permissions with test users"
    echo "3. Run cleanup when done: ./scripts/cleanup-namespaces-$VERSION.sh"
}

# Handle help flags
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"
