#!/bin/bash

# Kyverno RBAC Automation Monitoring Script
# Updated with correct namespace and improved monitoring

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
KYVERNO_NAMESPACE="kyverno"
GROUP_PATTERN="app-ocp-rbac"
CLUSTER_POLICY_NAME="generate-cluster-rolebindings"
NAMESPACE_POLICY_NAME="generate-namespace-rolebindings"

# Auto-detect available policies
CLUSTER_POLICY_EXISTS=$(kubectl get clusterpolicy "$CLUSTER_POLICY_NAME" 2>/dev/null | grep -c "$CLUSTER_POLICY_NAME")
NAMESPACE_POLICY_EXISTS=$(kubectl get clusterpolicy "$NAMESPACE_POLICY_NAME" 2>/dev/null | grep -c "$NAMESPACE_POLICY_NAME")

echo -e "${GREEN}=== Kyverno RBAC Automation Health Check ===${NC}"
echo -e "${BLUE}Namespace: ${KYVERNO_NAMESPACE}${NC}"
echo -e "${BLUE}Policies: ${NC}"
if [ "$CLUSTER_POLICY_EXISTS" -gt 0 ]; then
    echo -e "${GREEN}  ✓ Cluster Policy: ${CLUSTER_POLICY_NAME}${NC}"
else
    echo -e "${YELLOW}  - Cluster Policy: ${CLUSTER_POLICY_NAME} (not found)${NC}"
fi
if [ "$NAMESPACE_POLICY_EXISTS" -gt 0 ]; then
    echo -e "${GREEN}  ✓ Namespace Policy: ${NAMESPACE_POLICY_NAME}${NC}"
else
    echo -e "${YELLOW}  - Namespace Policy: ${NAMESPACE_POLICY_NAME} (not found)${NC}"
fi
echo ""

# 1. Check Kyverno pods status
echo -e "${YELLOW}1. Kyverno Pod Status:${NC}"
kubectl get pods -n ${KYVERNO_NAMESPACE} -o wide
echo ""

# Check if all pods are running
pods_not_running=$(kubectl get pods -n ${KYVERNO_NAMESPACE} --no-headers | grep -v "Running" | wc -l)
if [ "$pods_not_running" -gt 0 ]; then
    echo -e "${RED}⚠️  Warning: $pods_not_running Kyverno pods are not running${NC}"
else
    echo -e "${GREEN}✅ All Kyverno pods are running${NC}"
fi

# 2. Check policy status
echo -e "\n${YELLOW}2. RBAC Policy Status:${NC}"

# Check cluster policy status
if [ "$CLUSTER_POLICY_EXISTS" -gt 0 ]; then
    cluster_policy_status=$(kubectl get clusterpolicies ${CLUSTER_POLICY_NAME} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    cluster_policy_reason=$(kubectl get clusterpolicies ${CLUSTER_POLICY_NAME} -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)
    if [ "$cluster_policy_status" = "True" ]; then
        echo -e "${GREEN}✅ Cluster Policy: Ready (${cluster_policy_reason})${NC}"
    else
        echo -e "${RED}❌ Cluster Policy: Not Ready (${cluster_policy_reason})${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Cluster Policy: Not deployed${NC}"
fi

# Check namespace policy status
if [ "$NAMESPACE_POLICY_EXISTS" -gt 0 ]; then
    namespace_policy_status=$(kubectl get clusterpolicies ${NAMESPACE_POLICY_NAME} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    namespace_policy_reason=$(kubectl get clusterpolicies ${NAMESPACE_POLICY_NAME} -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)
    if [ "$namespace_policy_status" = "True" ]; then
        echo -e "${GREEN}✅ Namespace Policy: Ready (${namespace_policy_reason})${NC}"
    else
        echo -e "${RED}❌ Namespace Policy: Not Ready (${namespace_policy_reason})${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Namespace Policy: Not deployed${NC}"
fi

# 3. Policy Error Analysis with Timestamps
echo -e "\n${YELLOW}3. Policy Error Analysis:${NC}"
echo -e "${BLUE}Analysis time: $(date)${NC}"

# Get policy errors using kubectl's standard output format (shows relative time)
cluster_policy_errors=$(kubectl get events --all-namespaces --field-selector reason=PolicyError 2>/dev/null | grep ${CLUSTER_POLICY_NAME} | head -3)
namespace_policy_errors=$(kubectl get events --all-namespaces --field-selector reason=PolicyError 2>/dev/null | grep ${NAMESPACE_POLICY_NAME} | head -3)
policy_errors="${cluster_policy_errors}${namespace_policy_errors}"

if [ ! -z "$policy_errors" ]; then
    echo -e "${YELLOW}Historical Policy Errors for ${POLICY_NAME}:${NC}"
    echo ""
    
    # Extract the most recent error's relative timestamp
    latest_error_line=$(echo "$policy_errors" | head -1)
    latest_error_time=$(echo "$latest_error_line" | awk '{print $2}')
    
    echo -e "${RED}📅 Most recent error occurred: ${latest_error_time} ago${NC}"
    
    # Color code based on recency
    if echo "$latest_error_time" | grep -E "[0-9]+s$" > /dev/null; then
        echo -e "${RED}🚨 Very recent! (less than 1 minute ago)${NC}"
        recent_errors=1
    elif echo "$latest_error_time" | grep -E "[0-9]+m$" > /dev/null; then
        minutes=$(echo "$latest_error_time" | sed 's/m$//')
        if [ "$minutes" -lt 10 ]; then
            echo -e "${RED}⚠️  Recent (${minutes} minutes ago)${NC}"
            recent_errors=1
        else
            echo -e "${YELLOW}⚠️  Moderately recent (${minutes} minutes ago)${NC}"
            recent_errors=1
        fi
    elif echo "$latest_error_time" | grep -E "[0-9]+h$" > /dev/null; then
        hours=$(echo "$latest_error_time" | sed 's/h$//')
        if [ "$hours" -lt 2 ]; then
            echo -e "${YELLOW}🕒 ${hours} hour(s) ago${NC}"
            recent_errors=1
        else
            echo -e "${GREEN}🕒 ${hours} hours ago (older)${NC}"
            recent_errors=0
        fi
    elif echo "$latest_error_time" | grep -E "[0-9]+d$" > /dev/null; then
        days=$(echo "$latest_error_time" | sed 's/d$//')
        echo -e "${GREEN}🕒 ${days} day(s) ago (old)${NC}"
        recent_errors=0
    else
        recent_errors=0
    fi
    
    echo ""
    echo -e "${BLUE}Error timeline (most recent first):${NC}"
    echo "$policy_errors" | head -3 | while read line; do
        age=$(echo "$line" | awk '{print $2}')
        namespace=$(echo "$line" | awk '{print $1}')
        # Truncate the message to avoid overwhelming output
        message=$(echo "$line" | cut -d' ' -f6- | cut -c1-80)
        echo -e "  ${YELLOW}[$age ago]${NC} ${BLUE}[$namespace]${NC} $message..."
    done
else
    echo -e "${GREEN}✅ No policy errors found for ${POLICY_NAME}${NC}"
    recent_errors=0
fi

# 4. Check resource counts and mapping
echo -e "\n${YELLOW}4. Resource Counts & Mapping:${NC}"

# Cluster-scoped resources
crb_count=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l)
cluster_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "${GROUP_PATTERN}" | grep -c "cluster" || echo 0)

# Namespace-scoped resources
rb_count=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l)
namespace_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "${GROUP_PATTERN}" | grep -c "ns" || echo 0)
total_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "${GROUP_PATTERN}" | wc -l)

# Test namespaces count
test_namespaces=$(kubectl get namespaces -l oim-ns-admin --no-headers 2>/dev/null | wc -l)
test_namespaces_edit=$(kubectl get namespaces -l oim-ns-edit --no-headers 2>/dev/null | wc -l)
test_namespaces_view=$(kubectl get namespaces -l oim-ns-view --no-headers 2>/dev/null | wc -l)
max_test_namespaces=$(echo "$test_namespaces $test_namespaces_edit $test_namespaces_view" | tr ' ' '\n' | sort -nr | head -1)

echo -e "${BLUE}Cluster-scoped Resources:${NC}"
echo "  Generated ClusterRoleBindings: $crb_count"
echo "  Cluster Groups: $cluster_group_count"

echo -e "${BLUE}Namespace-scoped Resources:${NC}"
echo "  Generated RoleBindings: $rb_count"
echo "  Namespace Groups: $namespace_group_count"
echo "  Test Namespaces (with labels): $max_test_namespaces"

echo -e "${BLUE}Overall Totals:${NC}"
echo "  Total Groups: $total_group_count"
echo "  Total Bindings: $((crb_count + rb_count))"

# Validation logic
cluster_mapping_ok=0
namespace_mapping_ok=0

if [ "$crb_count" -eq "$cluster_group_count" ] && [ "$crb_count" -gt 0 ]; then
    echo -e "${GREEN}✅ Cluster mapping: Perfect 1:1 (Groups:$cluster_group_count ↔ CRBs:$crb_count)${NC}"
    cluster_mapping_ok=1
elif [ "$cluster_group_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Cluster mapping: Mismatch (Groups:$cluster_group_count vs CRBs:$crb_count)${NC}"
else
    echo -e "${YELLOW}ℹ️  No cluster-scoped resources found${NC}"
fi

if [ "$rb_count" -gt 0 ]; then
    expected_rb_count=$((namespace_group_count * max_test_namespaces))
    if [ "$rb_count" -eq "$expected_rb_count" ]; then
        echo -e "${GREEN}✅ Namespace mapping: Perfect (Groups:$namespace_group_count × NSs:$max_test_namespaces = RBs:$rb_count)${NC}"
        namespace_mapping_ok=1
    else
        echo -e "${YELLOW}⚠️  Namespace mapping: Expected ~$expected_rb_count RoleBindings, found $rb_count${NC}"
        echo -e "    ${BLUE}(May be normal during initial generation or with selective labels)${NC}"
    fi
else
    echo -e "${YELLOW}ℹ️  No namespace-scoped RoleBindings found${NC}"
fi

# Show actual resources
echo -e "\n${BLUE}Current OpenShift Groups:${NC}"
cluster_groups=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "${GROUP_PATTERN}" | grep "cluster")
namespace_groups=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "${GROUP_PATTERN}" | grep "ns")

if [ ! -z "$cluster_groups" ]; then
    echo -e "  ${YELLOW}Cluster-scoped Groups:${NC}"
    echo "$cluster_groups" | awk '{print "    - " $1}'
fi

if [ ! -z "$namespace_groups" ]; then
    echo -e "  ${YELLOW}Namespace-scoped Groups:${NC}"
    echo "$namespace_groups" | awk '{print "    - " $1}'
fi

if [ -z "$cluster_groups" ] && [ -z "$namespace_groups" ]; then
    echo "  None found"
fi

echo -e "\n${BLUE}Current Kyverno-managed Bindings:${NC}"
cluster_bindings=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null)
namespace_bindings=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null)

if [ ! -z "$cluster_bindings" ]; then
    echo -e "  ${YELLOW}ClusterRoleBindings:${NC}"
    echo "$cluster_bindings" | awk '{print "    - " $1 " (" $2 ")"}'
fi

if [ ! -z "$namespace_bindings" ]; then
    echo -e "  ${YELLOW}RoleBindings (by namespace):${NC}"
    echo "$namespace_bindings" | head -10 | awk '{print "    - [" $1 "] " $2 " (" $3 ")"}'
    rb_total=$(echo "$namespace_bindings" | wc -l)
    if [ "$rb_total" -gt 10 ]; then
        echo "    ... and $((rb_total-10)) more"
    fi
fi

if [ -z "$cluster_bindings" ] && [ -z "$namespace_bindings" ]; then
    echo "  None found"
fi

# 5. Recent Generation Activity Analysis
echo -e "\n${YELLOW}5. Recent Generation Activity:${NC}"

# Check for generation activity with improved parsing
cluster_generation_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --tail=200 --since=1h 2>/dev/null | grep "created generate target resource.*ClusterRoleBinding" 2>/dev/null)
namespace_generation_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --tail=200 --since=1h 2>/dev/null | grep "created generate target resource.*RoleBinding" 2>/dev/null)

recent_cluster_generations=$(echo "$cluster_generation_logs" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
recent_namespace_generations=$(echo "$namespace_generation_logs" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
total_recent_generations=$((recent_cluster_generations + recent_namespace_generations))

echo "Recent activity (last hour):"
echo "  ClusterRoleBinding generations: $recent_cluster_generations"
echo "  RoleBinding generations: $recent_namespace_generations"
echo "  Total generations: $total_recent_generations"

if [ "$total_recent_generations" -gt 0 ]; then
    echo -e "${GREEN}✅ Recent generation activity detected${NC}"
    echo -e "${BLUE}Latest generations:${NC}"
    
    # Show cluster generations
    if [ "$recent_cluster_generations" -gt 0 ]; then
        echo -e "  ${YELLOW}ClusterRoleBindings:${NC}"
        filtered_cluster_logs=$(echo "$cluster_generation_logs" | grep -v '^[[:space:]]*$')
        if [ ! -z "$filtered_cluster_logs" ]; then
            echo "$filtered_cluster_logs" | tail -3 | while IFS= read -r line; do
                resource_name=$(echo "$line" | grep -o 'app-ocp-rbac[^[:space:]]*-crb' | head -1)
                if [ ! -z "$resource_name" ]; then
                    echo -e "    ${GREEN}✓${NC} $resource_name"
                fi
            done
        fi
    fi
    
    # Show namespace generations
    if [ "$recent_namespace_generations" -gt 0 ]; then
        echo -e "  ${YELLOW}RoleBindings:${NC}"
        filtered_namespace_logs=$(echo "$namespace_generation_logs" | grep -v '^[[:space:]]*$')
        if [ ! -z "$filtered_namespace_logs" ]; then
            echo "$filtered_namespace_logs" | tail -5 | while IFS= read -r line; do
                # Extract namespace and RoleBinding name
                namespace_info=$(echo "$line" | grep -o '/[^/]*/[^[:space:]]*-rb' | head -1)
                if [ ! -z "$namespace_info" ]; then
                    echo -e "    ${GREEN}✓${NC} $namespace_info"
                fi
            done
        fi
    fi
else
    echo -e "${YELLOW}ℹ️  No generation activity in the last hour${NC}"
    echo -e "${BLUE}This could indicate:${NC}"
    echo "  - No new groups created recently"
    echo "  - System is stable with existing resources"
    echo "  - Check if any groups or namespaces were modified"
fi

# 6. Comprehensive Health Summary
echo -e "\n${YELLOW}6. Health Summary:${NC}"
echo -e "${BLUE}Assessment time: $(date)${NC}"
echo ""

health_issues=0
warnings=0

# Check pod health
if [ "$pods_not_running" -gt 0 ]; then
    echo -e "${RED}❌ Pod Health: $pods_not_running Kyverno pods not running${NC}"
    ((health_issues++))
else
    echo -e "${GREEN}✅ Pod Health: All Kyverno pods running${NC}"
fi

# Check policy status
if [ "$CLUSTER_POLICY_EXISTS" -gt 0 ] && [ "$cluster_policy_status" != "True" ]; then
    echo -e "${RED}❌ Cluster Policy Status: Not ready${NC}"
    ((health_issues++))
elif [ "$NAMESPACE_POLICY_EXISTS" -gt 0 ] && [ "$namespace_policy_status" != "True" ]; then
    echo -e "${RED}❌ Namespace Policy Status: Not ready${NC}"
    ((health_issues++))
else
    policy_ready_count=0
    if [ "$CLUSTER_POLICY_EXISTS" -gt 0 ] && [ "$cluster_policy_status" = "True" ]; then
        ((policy_ready_count++))
    fi
    if [ "$NAMESPACE_POLICY_EXISTS" -gt 0 ] && [ "$namespace_policy_status" = "True" ]; then
        ((policy_ready_count++))
    fi
    total_policies=$((CLUSTER_POLICY_EXISTS + NAMESPACE_POLICY_EXISTS))
    if [ "$policy_ready_count" -eq "$total_policies" ] && [ "$total_policies" -gt 0 ]; then
        echo -e "${GREEN}✅ Policy Status: All policies ready and operational${NC}"
    elif [ "$policy_ready_count" -gt 0 ]; then
        echo -e "${YELLOW}⚠️  Policy Status: $policy_ready_count/$total_policies policies ready${NC}"
        ((warnings++))
    else
        echo -e "${YELLOW}⚠️  Policy Status: No policies deployed${NC}"
        ((warnings++))
    fi
fi

# Check error status
if [ "$recent_errors" -gt 0 ]; then
    echo -e "${RED}❌ Error Status: Recent policy errors detected${NC}"
    ((health_issues++))
else
    echo -e "${GREEN}✅ Error Status: No recent policy errors${NC}"
fi

# Check resource mapping
if [ "$cluster_mapping_ok" -eq 1 ] && [ "$namespace_mapping_ok" -eq 1 ]; then
    echo -e "${GREEN}✅ Resource Mapping: Perfect mapping for all scopes${NC}"
elif [ "$cluster_mapping_ok" -eq 1 ] || [ "$namespace_mapping_ok" -eq 1 ]; then
    echo -e "${YELLOW}⚠️  Resource Mapping: Partial mapping success${NC}"
    ((warnings++))
else
    echo -e "${YELLOW}⚠️  Resource Mapping: Issues detected in resource mapping${NC}"
    ((warnings++))
fi

# Check generation activity
if [ "$total_recent_generations" -eq 0 ] && [ "$total_group_count" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Generation Activity: No recent activity (stable system)${NC}"
    ((warnings++))
else
    echo -e "${GREEN}✅ Generation Activity: System actively generating resources${NC}"
fi

echo ""
echo -e "${BLUE}Overall Assessment:${NC}"
if [ "$health_issues" -eq 0 ] && [ "$warnings" -eq 0 ]; then
    echo -e "${GREEN}✅ EXCELLENT: System is fully healthy - all checks passed${NC}"
elif [ "$health_issues" -eq 0 ]; then
    echo -e "${YELLOW}⚠️  GOOD: System is operational with $warnings minor warning(s)${NC}"
else
    echo -e "${RED}❌ ATTENTION: Found $health_issues critical issue(s) and $warnings warning(s)${NC}"
    echo -e "${RED}   Action required - check details above${NC}"
fi

# Recommendations
echo ""
echo -e "${BLUE}Quick Actions:${NC}"
if [ "$health_issues" -gt 0 ] || [ "$warnings" -gt 0 ]; then
    echo "  - Review detailed sections above for specific issues"
    echo "  - Use './scripts/watch-kyverno-rbac.sh' for real-time monitoring"
    if [ "$recent_errors" -gt 0 ]; then
        echo "  - Check RBAC permissions if policy errors persist"
    fi
    if [ "$crb_count" -ne "$cluster_group_count" ] || [ "$rb_count" -eq 0 ]; then
        echo "  - Wait 1-2 minutes for eventual consistency"
    fi
else
    echo "  - System is healthy, continue normal operations"
    echo "  - Consider running this check periodically"
fi

echo -e "\n${GREEN}=== Health Check Complete ===${NC}"
