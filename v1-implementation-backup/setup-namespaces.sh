#!/bin/bash

# Setup Namespaces v2 - Uses rbac.oim-ns-{role}/{group-name}: enabled label structure
# This version supports multiple groups per role without comma-separated values

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Setting up Test Namespaces v2 ===${NC}"
echo -e "${BLUE}Using new label structure: rbac.oim-ns-{role}/{group-name}: enabled${NC}"
echo ""

# Function to create namespace with v2 labels
create_namespace_v2() {
    local name="$1"
    local description="$2"
    shift 2
    
    echo -e "${YELLOW}Creating namespace: $name${NC}"
    echo -e "${BLUE}  Description: $description${NC}"
    
    # Start building the kubectl command
    local cmd="kubectl create namespace $name --dry-run=client -o yaml | kubectl apply -f -"
    
    # Create the namespace first
    kubectl create namespace "$name" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    
    # Add the management label
    kubectl label namespace "$name" "app.kubernetes.io/managed-by=kyverno-test" --overwrite
    
    # Process remaining arguments as label assignments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --admin)
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    echo -e "${GREEN}    Admin: $1${NC}"
                    kubectl label namespace "$name" "rbac.oim-ns-admin/$1=enabled" --overwrite
                    shift
                done
                ;;
            --edit)
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    echo -e "${GREEN}    Edit: $1${NC}"
                    kubectl label namespace "$name" "rbac.oim-ns-edit/$1=enabled" --overwrite
                    shift
                done
                ;;
            --view)
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                    echo -e "${GREEN}    View: $1${NC}"
                    kubectl label namespace "$name" "rbac.oim-ns-view/$1=enabled" --overwrite
                    shift
                done
                ;;
            --exclude)
                echo -e "${YELLOW}    Excluded from RBAC${NC}"
                kubectl label namespace "$name" "kyverno.io/exclude-rbac=true" --overwrite
                shift
                ;;
            *)
                echo -e "${RED}    Unknown option: $1${NC}"
                shift
                ;;
        esac
    done
    
    echo ""
}

# Demo namespace - single groups per role
create_namespace_v2 "demo-ns" "Demo namespace for testing basic RBAC" \
    --admin "app-ocp-rbac-demo-ns-admin" \
    --edit "app-ocp-rbac-demo-ns-developer" \
    --view "app-ocp-rbac-demo-ns-audit"

# Team Alpha - multiple edit groups 
create_namespace_v2 "team-alpha-dev" "Team Alpha development environment" \
    --admin "app-ocp-rbac-alpha-ns-admin" \
    --edit "app-ocp-rbac-alpha-ns-developer" "app-ocp-rbac-platform-ns-developer" \
    --view "app-ocp-rbac-alpha-ns-audit"

# Team Beta - multiple admin groups
create_namespace_v2 "team-beta-prod" "Team Beta production environment" \
    --admin "app-ocp-rbac-beta-ns-admin" "app-ocp-rbac-solo-ns-admin" \
    --edit "app-ocp-rbac-beta-ns-developer"

# Shared tools - platform teams
create_namespace_v2 "shared-tools" "Shared tools and utilities" \
    --admin "app-ocp-rbac-platform-ns-admin" \
    --view "app-ocp-rbac-platform-ns-audit" "app-ocp-rbac-demo-ns-audit"

# OpenShift config (system namespace) - opt-in
kubectl label namespace "openshift-config" "rbac.oim-ns-admin/app-ocp-rbac-platform-ns-admin=enabled" --overwrite
kubectl label namespace "openshift-config" "kyverno.io/exclude-rbac=false" --overwrite
echo -e "${YELLOW}Updated openshift-config namespace with platform admin access${NC}"
echo ""

# Kill switch test (excluded namespace)
create_namespace_v2 "kill-switch-test" "Testing RBAC exclusion" \
    --admin "app-ocp-rbac-demo-ns-admin" \
    --exclude

echo -e "${GREEN}=== Namespace Setup Complete ===${NC}"
echo ""

echo -e "${BLUE}Summary of created namespaces with v2 labels:${NC}"
kubectl get namespaces -l "app.kubernetes.io/managed-by=kyverno-test" -o custom-columns="NAME:.metadata.name,ADMIN_LABELS:.metadata.labels" --no-headers | while read ns labels; do
    echo -e "${YELLOW}$ns:${NC}"
    echo "$labels" | tr ',' '\n' | grep "rbac.oim-ns-" | sed 's/^/  /'
    echo ""
done

echo -e "${BLUE}Verification commands:${NC}"
echo "# View all v2 namespaces:"
echo "kubectl get namespaces -l app.kubernetes.io/managed-by=kyverno-test --show-labels"
echo ""
echo "# View admin groups:"
echo "kubectl get namespaces -l rbac.oim-ns-admin/ --show-labels"
echo ""
echo "# View specific group access:"
echo "kubectl get namespaces -l rbac.oim-ns-admin/app-ocp-rbac-beta-ns-admin=enabled"
