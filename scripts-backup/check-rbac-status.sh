#!/bin/bash

# Kyverno RBAC System V2 Status Checker
# This script provides comprehensive status monitoring of the Kyverno RBAC system

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Kyverno RBAC System V2 Status Check${NC}\n"

# Function to print section headers
print_section() {
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}$(printf '%*s' ${#1} '' | tr ' ' '=')${NC}"
}

# Check Kyverno installation and readiness
print_section "1. Kyverno System Status"
if kubectl get namespace kyverno >/dev/null 2>&1; then
    echo -e "${GREEN}✅${NC} Kyverno namespace exists"
    
    # Check deployment status
    if kubectl get deployment kyverno -n kyverno >/dev/null 2>&1; then
        READY_REPLICAS=$(kubectl get deployment kyverno -n kyverno -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED_REPLICAS=$(kubectl get deployment kyverno -n kyverno -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
        
        if [ "$READY_REPLICAS" = "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" != "0" ]; then
            echo -e "${GREEN}✅${NC} Kyverno deployment ready ($READY_REPLICAS/$DESIRED_REPLICAS)"
        else
            echo -e "${YELLOW}⚠️ ${NC} Kyverno deployment not fully ready ($READY_REPLICAS/$DESIRED_REPLICAS)"
        fi
        
        # Show version
        KYVERNO_VERSION=$(kubectl get deployment kyverno -n kyverno -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://')
        echo -e "${BLUE}ℹ️ ${NC} Kyverno version: ${KYVERNO_VERSION:-unknown}"
    else
        echo -e "${RED}❌${NC} Kyverno deployment not found"
    fi
else
    echo -e "${RED}❌${NC} Kyverno namespace not found"
fi

echo ""

# Check policy deployment status
print_section "2. Policy Deployment Status"

POLICIES=(
    "system-namespace-rbac-control-policy"
    "generate-cluster-rolebindings-policy" 
    "enforce-rbac-standards-policy-v2-numbered"
    "generate-namespace-rolebindings-policy-v2-numbered"
)

POLICY_DESCRIPTIONS=(
    "System Namespace Control (include/exclude precedence)"
    "Cluster RoleBinding Generation"
    "RBAC Standards Enforcement (V2)"
    "Namespace RoleBinding Generation (V2)"
)

for i in "${!POLICIES[@]}"; do
    if kubectl get cpol "${POLICIES[$i]}" >/dev/null 2>&1; then
        STATUS=$(kubectl get cpol "${POLICIES[$i]}" -o jsonpath='{.status.ready}' 2>/dev/null)
        if [ "$STATUS" = "true" ]; then
            echo -e "${GREEN}✅${NC} ${POLICY_DESCRIPTIONS[$i]}"
        else
            echo -e "${YELLOW}⚠️ ${NC} ${POLICY_DESCRIPTIONS[$i]} (not ready)"
        fi
    else
        echo -e "${RED}❌${NC} ${POLICY_DESCRIPTIONS[$i]} (not found)"
    fi
done

echo ""

# Check system namespace labeling
print_section "3. System Namespace RBAC Labels"

echo -e "${BLUE}System namespaces with include/exclude labels:${NC}"
kubectl get ns -o custom-columns="NAME:.metadata.name,INCLUDE:.metadata.labels.kyverno\.io/include-rbac,EXCLUDE:.metadata.labels.kyverno\.io/exclude-rbac" --no-headers | \
    grep -E "(kube-|openshift-|istio-|monitoring)" | \
    while IFS=$'\t' read -r ns include exclude; do
        if [ "$include" = "true" ]; then
            echo -e "  ${GREEN}✅${NC} $ns (include-rbac: true)"
        elif [ "$exclude" = "true" ]; then
            echo -e "  ${YELLOW}🚫${NC} $ns (exclude-rbac: true)"
        else
            echo -e "  ${BLUE}ℹ️ ${NC} $ns (no rbac labels)"
        fi
    done

echo ""

# Check OIM group labels in namespaces
print_section "4. OIM Group Labels (Sample Namespaces)"

echo -e "${BLUE}Namespaces with OIM group labels:${NC}"
kubectl get ns -o json | jq -r '.items[] | select(.metadata.labels | has("kyverno.io/iam-admin-groups-1") or has("kyverno.io/iam-edit-groups-1") or has("kyverno.io/iam-view-groups-1")) | .metadata.name' | head -10 | \
    while read -r ns; do
        if [ -n "$ns" ]; then
            ADMIN_GROUPS=$(kubectl get ns "$ns" -o jsonpath='{.metadata.labels.kyverno\.io/iam-admin-groups-1}' 2>/dev/null || echo "")
            EDIT_GROUPS=$(kubectl get ns "$ns" -o jsonpath='{.metadata.labels.kyverno\.io/iam-edit-groups-1}' 2>/dev/null || echo "")
            VIEW_GROUPS=$(kubectl get ns "$ns" -o jsonpath='{.metadata.labels.kyverno\.io/iam-view-groups-1}' 2>/dev/null || echo "")
            
            echo -e "  ${GREEN}📂${NC} $ns"
            [ -n "$ADMIN_GROUPS" ] && echo -e "    ${RED}👑${NC} Admin: $ADMIN_GROUPS"
            [ -n "$EDIT_GROUPS" ] && echo -e "    ${YELLOW}✏️ ${NC} Edit: $EDIT_GROUPS"
            [ -n "$VIEW_GROUPS" ] && echo -e "    ${BLUE}👀${NC} View: $VIEW_GROUPS"
        fi
    done

echo ""

# Check generated RoleBindings
print_section "5. Generated RoleBindings (Sample)"

echo -e "${BLUE}Recently generated RoleBindings by Kyverno:${NC}"
kubectl get rolebindings -A -o json | jq -r '.items[] | select(.metadata.labels."app.kubernetes.io/managed-by" == "kyverno") | "\(.metadata.namespace)/\(.metadata.name)"' | head -10 | \
    while IFS='/' read -r ns rb_name; do
        if [ -n "$ns" ] && [ -n "$rb_name" ]; then
            ROLE=$(kubectl get rolebinding "$rb_name" -n "$ns" -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "unknown")
            SUBJECTS=$(kubectl get rolebinding "$rb_name" -n "$ns" -o jsonpath='{.subjects[*].name}' 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}🔗${NC} $ns/$rb_name (role: $ROLE, subjects: $SUBJECTS)"
        fi
    done

echo ""

# Check ClusterRoleBindings
print_section "6. Generated ClusterRoleBindings (Sample)"

echo -e "${BLUE}ClusterRoleBindings generated by Kyverno:${NC}"
kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.metadata.labels."app.kubernetes.io/managed-by" == "kyverno") | .metadata.name' | head -5 | \
    while read -r crb_name; do
        if [ -n "$crb_name" ]; then
            ROLE=$(kubectl get clusterrolebinding "$crb_name" -o jsonpath='{.roleRef.name}' 2>/dev/null || echo "unknown")
            SUBJECTS=$(kubectl get clusterrolebinding "$crb_name" -o jsonpath='{.subjects[*].name}' 2>/dev/null || echo "unknown")
            echo -e "  ${GREEN}🌐${NC} $crb_name (role: $ROLE, subjects: $SUBJECTS)"
        fi
    done

echo ""

# Check for policy violations or events
print_section "7. Recent Kyverno Events"

echo -e "${BLUE}Recent Kyverno events (last 10):${NC}"
kubectl get events -A --sort-by='.lastTimestamp' | grep -i kyverno | tail -10 | \
    while read -r line; do
        if echo "$line" | grep -q "Warning"; then
            echo -e "  ${YELLOW}⚠️ ${NC} $line"
        else
            echo -e "  ${GREEN}ℹ️ ${NC} $line"
        fi
    done || echo -e "  ${BLUE}ℹ️ ${NC} No recent Kyverno events found"

echo ""

# Summary and recommendations
print_section "8. Summary & Recommendations"

# Count policies
READY_POLICIES=$(kubectl get cpol --no-headers 2>/dev/null | grep -c "True" || echo "0")
TOTAL_EXPECTED=4

echo -e "${BLUE}📊 System Overview:${NC}"
echo -e "  • Ready policies: $READY_POLICIES/$TOTAL_EXPECTED"

if [ "$READY_POLICIES" = "$TOTAL_EXPECTED" ]; then
    echo -e "  • Status: ${GREEN}✅ All policies active${NC}"
else
    echo -e "  • Status: ${YELLOW}⚠️  Some policies missing/not ready${NC}"
fi

echo -e "\n${BLUE}💡 Next Actions:${NC}"
if [ "$READY_POLICIES" -lt "$TOTAL_EXPECTED" ]; then
    echo -e "  1. Run: ${YELLOW}./scripts/deploy-rbac-policies.sh${NC} to deploy missing policies"
fi
echo -e "  2. Monitor logs: ${YELLOW}kubectl logs -n kyverno deployment/kyverno -f${NC}"
echo -e "  3. Test with new namespace: ${YELLOW}kubectl create namespace test-$(date +%s)${NC}"
echo -e "  4. Validate RoleBindings are created when OIM groups are added"

echo -e "\n${GREEN}🎉 Status check complete!${NC}"
