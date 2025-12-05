#!/bin/bash

# Kyverno RBAC Policies V2 Deployment Script
# This script deploys all V2 Kyverno policies in the correct order

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Deploying Kyverno RBAC Policies V2${NC}\n"

# Check if Kyverno is running
if ! kubectl get deployment kyverno -n kyverno >/dev/null 2>&1; then
    echo -e "${RED}❌ Kyverno deployment not found. Please install Kyverno first.${NC}"
    exit 1
fi

# Check Kyverno readiness
READY_REPLICAS=$(kubectl get deployment kyverno -n kyverno -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
DESIRED_REPLICAS=$(kubectl get deployment kyverno -n kyverno -o jsonpath='{.spec.replicas}' 2>/dev/null)

if [ "$READY_REPLICAS" != "$DESIRED_REPLICAS" ] || [ -z "$READY_REPLICAS" ]; then
    echo -e "${YELLOW}⚠️  Kyverno is not fully ready. Ready: $READY_REPLICAS/$DESIRED_REPLICAS${NC}"
    echo -e "${YELLOW}Continuing with deployment but policies may not take effect immediately...${NC}\n"
fi

# Define policy files in deployment order
POLICIES=(
    "system-namespace-rbac-control-policy.yaml"
    "generate-cluster-rolebindings-policy.yaml" 
    "enforce-rbac-standards-policy-v2-numbered.yaml"
    "generate-namespace-rolebindings-policy-v2-numbered.yaml"
)

DESCRIPTIONS=(
    "System Namespace RBAC Control (include/exclude precedence)"
    "Cluster-level RoleBinding Generation"
    "RBAC Standards Enforcement (V2 numbered labels)"
    "Namespace RoleBinding Generation (V2 numbered labels)"
)

# Check all files exist before starting
echo -e "${BLUE}📋 Checking policy files...${NC}"
for i in "${!POLICIES[@]}"; do
    if [ ! -f "${POLICIES[$i]}" ]; then
        echo -e "${RED}❌ Policy file not found: ${POLICIES[$i]}${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅${NC} ${POLICIES[$i]}"
done

echo ""

# Deploy policies in order
for i in "${!POLICIES[@]}"; do
    STEP=$((i + 1))
    echo -e "${BLUE}Step $STEP/4: Deploying ${DESCRIPTIONS[$i]}${NC}"
    echo -e "${BLUE}File: ${POLICIES[$i]}${NC}"
    
    if kubectl apply -f "${POLICIES[$i]}"; then
        echo -e "${GREEN}✅ Successfully applied ${POLICIES[$i]}${NC}"
    else
        echo -e "${RED}❌ Failed to apply ${POLICIES[$i]}${NC}"
        echo -e "${YELLOW}Continuing with remaining policies...${NC}"
    fi
    echo ""
done

echo -e "${GREEN}🎉 Deployment complete!${NC}\n"

# Show applied policies
echo -e "${BLUE}📊 Checking applied Kyverno policies:${NC}"
kubectl get cpol | grep -E "(system-namespace|generate-cluster|enforce-rbac|generate-namespace)" || echo -e "${YELLOW}No matching policies found${NC}"

echo -e "\n${BLUE}💡 Next steps:${NC}"
echo "1. Monitor Kyverno logs: kubectl logs -n kyverno deployment/kyverno -f"
echo "2. Test with a new namespace: kubectl create namespace test-rbac"
echo "3. Add OIM groups to test namespace and observe RoleBinding generation"
echo "4. Check system namespaces have correct include/exclude labels"

echo -e "\n${YELLOW}Note: Existing namespaces will be processed as they receive updates.${NC}"
echo -e "${YELLOW}For immediate processing of existing namespaces, consider manual annotation updates.${NC}"
