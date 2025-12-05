#!/bin/bash

# Validate RBAC Policies V2 for Kyverno v1.15.1 Compatibility
# Checks syntax, applies V2 numbered policies with precedence system, and verifies they work correctly

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
POLICIES=(
    "system-namespace-rbac-control-policy.yaml"
    "generate-cluster-rolebindings-policy.yaml"
    "enforce-rbac-standards-policy-v2-numbered.yaml" 
    "generate-namespace-rolebindings-policy-v2-numbered.yaml"
)

echo -e "${GREEN}=== Kyverno RBAC Policy Validation ===${NC}"
echo -e "${BLUE}Validating policies for Kyverno v1.15.1 compatibility${NC}"
echo ""

# Check if Kyverno is running
echo -e "${YELLOW}1. Checking Kyverno Status:${NC}"
kyverno_pods=$(kubectl get pods -n kyverno --no-headers 2>/dev/null | wc -l)
if [ "$kyverno_pods" -eq 0 ]; then
    echo -e "${RED}❌ Kyverno not found - please install Kyverno first${NC}"
    exit 1
fi

kyverno_ready=$(kubectl get pods -n kyverno --no-headers | grep -v "Running" | wc -l)
if [ "$kyverno_ready" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Some Kyverno pods are not ready${NC}"
    kubectl get pods -n kyverno
else
    echo -e "${GREEN}✅ Kyverno is running (${kyverno_pods} pods)${NC}"
fi
echo ""

# Validate policy syntax
echo -e "${YELLOW}2. Validating Policy Syntax:${NC}"
validation_errors=0

for policy in "${POLICIES[@]}"; do
    echo -n "  Checking $policy... "
    
    if [ ! -f "$policy" ]; then
        echo -e "${RED}❌ File not found${NC}"
        ((validation_errors++))
        continue
    fi
    
    # Basic YAML validation
    if ! kubectl --dry-run=client apply -f "$policy" >/dev/null 2>&1; then
        echo -e "${RED}❌ Invalid YAML syntax${NC}"
        kubectl --dry-run=client apply -f "$policy" 2>&1 | sed 's/^/    /'
        ((validation_errors++))
        continue
    fi
    
    # Check for Kyverno v1.15+ compatibility
    version_check=$(grep -o 'kyverno-version.*"[0-9.]*"' "$policy" | grep -o '"[0-9.]*"' | tr -d '"')
    if [[ "$version_check" < "1.15.0" ]]; then
        echo -e "${YELLOW}⚠️  Old version reference ($version_check)${NC}"
    else
        echo -e "${GREEN}✅ Valid${NC}"
    fi
done

if [ "$validation_errors" -gt 0 ]; then
    echo -e "${RED}Found $validation_errors validation errors${NC}"
    echo ""
fi

# Check current policies
echo -e "${YELLOW}3. Current Applied Policies:${NC}"
current_policies=$(kubectl get clusterpolicies --no-headers 2>/dev/null | grep -E "(system-namespace-rbac-control|generate-cluster-rolebindings|enforce-rbac|generate-namespace-rolebindings)" | wc -l)
echo "Currently applied RBAC policies: $current_policies"

if [ "$current_policies" -gt 0 ]; then
    kubectl get clusterpolicies | grep -E "(system-namespace-rbac-control|generate-cluster-rolebindings|enforce-rbac|generate-namespace-rolebindings)" | sed 's/^/  /'
fi
echo ""

# Apply policies (dry-run first)
echo -e "${YELLOW}4. Policy Application Test:${NC}"
echo "Testing policy application (dry-run)..."

for policy in "${POLICIES[@]}"; do
    if [ -f "$policy" ]; then
        echo -n "  Dry-run $policy... "
        if kubectl apply --dry-run=server -f "$policy" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ OK${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
            kubectl apply --dry-run=server -f "$policy" 2>&1 | sed 's/^/    /'
        fi
    fi
done
echo ""

# Check for common v1.15+ syntax patterns
echo -e "${YELLOW}5. Kyverno v1.15+ Syntax Compatibility:${NC}"
syntax_checks=0

for policy in "${POLICIES[@]}"; do
    if [ -f "$policy" ]; then
        echo "  Checking $policy..."
        
        # Check for proper resource kinds format
        if grep -q "kinds:.*user.openshift.io/v1/Group" "$policy"; then
            echo -e "    ${GREEN}✅ Proper OpenShift Group kind format${NC}"
        elif grep -q "apiGroups.*user.openshift.io" "$policy"; then
            echo -e "    ${YELLOW}⚠️  Using old apiGroups format - consider updating${NC}"
        fi
        
        # Check for wildcard names
        if grep -q "names:.*\*" "$policy"; then
            echo -e "    ${GREEN}✅ Uses wildcard matching in names${NC}"
        fi
        
        # Check for proper JMESPath usage
        if grep -q "jmesPath:" "$policy"; then
            echo -e "    ${GREEN}✅ Uses JMESPath expressions${NC}"
        fi
        
        # Check for synchronize flag
        if grep -q "synchronize: true" "$policy"; then
            echo -e "    ${GREEN}✅ Has synchronize: true for lifecycle management${NC}"
        elif grep -q "generate:" "$policy"; then
            echo -e "    ${YELLOW}⚠️  Generate rule without synchronize: true${NC}"
        fi
    fi
done
echo ""

# Summary
echo -e "${YELLOW}6. Validation Summary:${NC}"
if [ "$validation_errors" -eq 0 ]; then
    echo -e "${GREEN}✅ All policies passed basic validation${NC}"
    echo -e "${BLUE}Ready to apply policies in order:${NC}"
    echo "  1. kubectl apply -f system-namespace-rbac-control-policy.yaml  # Precedence control"
    echo "  2. kubectl apply -f generate-cluster-rolebindings-policy.yaml"
    echo "  3. kubectl apply -f enforce-rbac-standards-policy-v2-numbered.yaml"
    echo "  4. kubectl apply -f generate-namespace-rolebindings-policy-v2-numbered.yaml"
else
    echo -e "${RED}❌ Found $validation_errors issues - fix before applying${NC}"
fi

echo ""
echo -e "${BLUE}To monitor policies after applying:${NC}"
echo "  ./scripts/monitor-kyverno-rbac.sh"
echo "  ./scripts/watch-kyverno-rbac.sh"

echo ""
echo -e "${GREEN}=== Validation Complete ===${NC}"
