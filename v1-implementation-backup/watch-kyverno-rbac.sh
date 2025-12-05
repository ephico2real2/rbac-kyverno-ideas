#!/bin/bash

# Interactive Kyverno RBAC Real-time Monitoring (v2)
# Improved with better signal handling and timeout options

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

KYVERNO_NAMESPACE="kyverno"
CLUSTER_POLICY_NAME="generate-cluster-rolebindings"
NAMESPACE_POLICY_NAME="generate-namespace-rolebindings"

# Auto-detect available policies
CLUSTER_POLICY_EXISTS=$(kubectl get clusterpolicy "$CLUSTER_POLICY_NAME" 2>/dev/null | grep -c "$CLUSTER_POLICY_NAME" || echo 0)
NAMESPACE_POLICY_EXISTS=$(kubectl get clusterpolicy "$NAMESPACE_POLICY_NAME" 2>/dev/null | grep -c "$NAMESPACE_POLICY_NAME" || echo 0)

# Global variable to track if we should return to menu
RETURN_TO_MENU=false

# Function to handle Ctrl+C gracefully
handle_interrupt() {
    echo -e "\n${GREEN}Stopping monitoring and returning to menu...${NC}"
    RETURN_TO_MENU=true
    return 0
}

show_menu() {
    clear
    echo -e "${GREEN}=== Kyverno RBAC Real-time Monitoring v2 ===${NC}"
    echo -e "${BLUE}Namespace: ${KYVERNO_NAMESPACE}${NC}"
    echo -e "${BLUE}Active Policies:${NC}"
    if [ "$CLUSTER_POLICY_EXISTS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ ${CLUSTER_POLICY_NAME}${NC}"
    fi
    if [ "$NAMESPACE_POLICY_EXISTS" -gt 0 ]; then
        echo -e "${GREEN}  ✓ ${NAMESPACE_POLICY_NAME}${NC}"
    fi
    if [ "$CLUSTER_POLICY_EXISTS" -eq 0 ] && [ "$NAMESPACE_POLICY_EXISTS" -eq 0 ]; then
        echo -e "${YELLOW}  No policies found${NC}"
    fi
    echo ""
    echo "Choose monitoring option:"
    echo "1) Watch ClusterRoleBinding generation logs (Enter to exit)"
    echo "2) Watch RoleBinding generation logs (Enter to exit)"
    echo "3) Policy error analysis with timestamps (Enter to exit)"
    echo "4) Monitor resource counts (Enter to stop)"
    echo "5) Watch Kyverno pod status (Enter to exit)"
    echo "6) Run full health check"
    echo "7) Recent activity summary with timestamps"
    echo "8) Exit"
    echo ""
    echo -n "Enter choice [1-8]: "
}

watch_generation_logs() {
    echo -e "${YELLOW}Watching ClusterRoleBinding generation logs...${NC}"
    echo -e "${BLUE}Press Enter to return to menu (or auto-return in 30s)${NC}"
    echo ""
    
    # Show recent activity first
    echo -e "${BLUE}Recent ClusterRoleBinding generations:${NC}"
    recent_cluster_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --tail=20 --since=10m 2>/dev/null | grep "ClusterRoleBinding")
    if [ ! -z "$recent_cluster_logs" ]; then
        echo "$recent_cluster_logs" | tail -5
    else
        echo "  No recent ClusterRoleBinding activity"
    fi
    echo ""
    
    # Use a simpler polling approach instead of streaming logs
    echo -e "${YELLOW}Monitoring for new generations (press Enter to exit)...${NC}"
    echo -e "${BLUE}Will check for new activity every 5 seconds${NC}"
    echo ""
    
    # Get starting point
    start_time=$(date -u +%s)
    
    # Monitor with polling approach
    timeout_reached=false
    for i in 1 2 3 4 5 6; do  # 6 iterations = 30 seconds max
        # Check if user pressed Enter (non-blocking)
        if read -t 5 -s; then
            echo -e "\n${GREEN}User requested return to menu...${NC}"
            break
        fi
        
        # Check for new log entries
        new_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --since="${start_time}s" 2>/dev/null | grep "ClusterRoleBinding" 2>/dev/null)
        
        if [ ! -z "$new_logs" ]; then
            echo -e "\n${GREEN}New activity detected:${NC}"
            echo "$new_logs" | tail -3
            echo ""
        fi
        
        # Show progress indicator
        echo -ne "\r${BLUE}Monitoring... (${i}/6 - press Enter to exit)${NC}"
        
        # Check if this is the last iteration
        if [ $i -eq 6 ]; then
            timeout_reached=true
        fi
    done
    
    if [ "$timeout_reached" = true ]; then
        echo -e "\n${YELLOW}30-second timeout reached...${NC}"
    fi
    
    echo -e "\n${GREEN}Returning to menu...${NC}"
    sleep 1
}

watch_namespace_generation_logs() {
    echo -e "${YELLOW}Watching RoleBinding generation logs...${NC}"
    echo -e "${BLUE}Press Enter to return to menu (or auto-return in 30s)${NC}"
    echo ""
    
    # Show recent activity first
    echo -e "${BLUE}Recent RoleBinding generations:${NC}"
    recent_namespace_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --tail=20 --since=10m 2>/dev/null | grep "RoleBinding")
    if [ ! -z "$recent_namespace_logs" ]; then
        echo "$recent_namespace_logs" | tail -5
    else
        echo "  No recent RoleBinding activity"
    fi
    echo ""
    
    # Use a simpler polling approach instead of streaming logs
    echo -e "${YELLOW}Monitoring for new RoleBinding generations (press Enter to exit)...${NC}"
    echo -e "${BLUE}Will check for new activity every 5 seconds${NC}"
    echo ""
    
    # Get starting point
    start_time=$(date -u +%s)
    
    # Monitor with polling approach
    timeout_reached=false
    for i in 1 2 3 4 5 6; do  # 6 iterations = 30 seconds max
        # Check if user pressed Enter (non-blocking)
        if read -t 5 -s; then
            echo -e "\n${GREEN}User requested return to menu...${NC}"
            break
        fi
        
        # Check for new log entries
        new_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --since="${start_time}s" 2>/dev/null | grep "RoleBinding" 2>/dev/null)
        
        if [ ! -z "$new_logs" ]; then
            echo -e "\n${GREEN}New RoleBinding activity detected:${NC}"
            echo "$new_logs" | tail -3
            echo ""
        fi
        
        # Show progress indicator
        echo -ne "\r${BLUE}Monitoring... (${i}/6 - press Enter to exit)${NC}"
        
        # Check if this is the last iteration
        if [ $i -eq 6 ]; then
            timeout_reached=true
        fi
    done
    
    if [ "$timeout_reached" = true ]; then
        echo -e "\n${YELLOW}30-second timeout reached...${NC}"
    fi
    
    echo -e "\n${GREEN}Returning to menu...${NC}"
    sleep 1
}

watch_policy_errors() {
    echo -e "${YELLOW}Policy Error Monitoring${NC}"
    echo -e "${BLUE}Current time: $(date)${NC}"
    echo -e "${BLUE}Press Enter to stop early and return to menu${NC}"
    echo ""
    
    # Get policy errors using kubectl's standard output format (shows relative time)
    cluster_policy_errors=$(kubectl get events --all-namespaces --field-selector reason=PolicyError 2>/dev/null | grep ${CLUSTER_POLICY_NAME} | head -3)
    namespace_policy_errors=$(kubectl get events --all-namespaces --field-selector reason=PolicyError 2>/dev/null | grep ${NAMESPACE_POLICY_NAME} | head -3)
    policy_errors="${cluster_policy_errors}${namespace_policy_errors}"
    
    if [ ! -z "$policy_errors" ]; then
        echo -e "${YELLOW}Historical Policy Errors:${NC}"
        echo ""
        
        # Extract the most recent error's relative timestamp
        latest_error_line=$(echo "$policy_errors" | head -1)
        latest_error_time=$(echo "$latest_error_line" | awk '{print $2}')
        
        echo -e "${RED}📅 Most recent error occurred: ${latest_error_time} ago${NC}"
        
        # Color code based on recency
        if echo "$latest_error_time" | grep -E "[0-9]+s$" > /dev/null; then
            echo -e "${RED}🚨 Very recent! (less than 1 minute ago)${NC}"
        elif echo "$latest_error_time" | grep -E "[0-9]+m$" > /dev/null; then
            minutes=$(echo "$latest_error_time" | sed 's/m$//')
            if [ "$minutes" -lt 10 ]; then
                echo -e "${RED}⚠️  Recent (${minutes} minutes ago)${NC}"
            else
                echo -e "${YELLOW}⚠️  Moderately recent (${minutes} minutes ago)${NC}"
            fi
        elif echo "$latest_error_time" | grep -E "[0-9]+h$" > /dev/null; then
            hours=$(echo "$latest_error_time" | sed 's/h$//')
            if [ "$hours" -lt 2 ]; then
                echo -e "${YELLOW}🕒 ${hours} hour(s) ago${NC}"
            else
                echo -e "${GREEN}🕒 ${hours} hours ago (older)${NC}"
            fi
        elif echo "$latest_error_time" | grep -E "[0-9]+d$" > /dev/null; then
            days=$(echo "$latest_error_time" | sed 's/d$//')
            echo -e "${GREEN}🕒 ${days} day(s) ago (old)${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}Error timeline (most recent first):${NC}"
        echo "$policy_errors" | head -3 | while read line; do
            age=$(echo "$line" | awk '{print $2}')
            namespace=$(echo "$line" | awk '{print $1}')
            # Truncate the message to avoid overwhelming output
            message=$(echo "$line" | cut -d' ' -f6- | cut -c1-100)
            echo -e "  ${YELLOW}[$age ago]${NC} ${BLUE}[$namespace]${NC} $message..."
        done
        echo ""
    else
        echo -e "${GREEN}✅ No policy errors found for ${POLICY_NAME}${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}Watching for new policy errors...${NC}"
    echo -e "${BLUE}Press Enter to return to menu (or auto-return in 30s)${NC}"
    echo ""
    
    # Start event monitoring in background
    kubectl get events --all-namespaces --field-selector reason=PolicyError -w 2>/dev/null &
    EVENT_PID=$!
    
    # Wait for user input or timeout (30 seconds)
    if read -t 30 -s; then
        echo -e "\n${GREEN}User requested return to menu...${NC}"
    else
        echo -e "\n${YELLOW}30-second timeout reached...${NC}"
    fi
    
    # Kill the event monitoring process
    kill $EVENT_PID 2>/dev/null
    wait $EVENT_PID 2>/dev/null
    
    echo -e "\n${GREEN}Returning to menu...${NC}"
    sleep 1
}

watch_resource_counts() {
    echo -e "${YELLOW}Monitoring resource counts (refreshing every 5 seconds)...${NC}"
    echo -e "${BLUE}Press Enter to stop and return to menu${NC}"
    echo ""
    
    while true; do
        # Clear the screen and show header
        clear
        echo -e "${YELLOW}Resource Count Monitor - $(date '+%H:%M:%S')${NC}"
        echo -e "${BLUE}Press Enter to return to menu${NC}"
        echo ""
        
        # Cluster-scoped resources
        crb_count=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l | tr -d ' ')
        cluster_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | grep -c "cluster" | tr -d ' ')
        
        # Namespace-scoped resources
        rb_count=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l | tr -d ' ')
        namespace_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | grep -c "ns" | tr -d ' ')
        total_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | wc -l | tr -d ' ')
        
        echo -e "${BLUE}Cluster-scoped:${NC}"
        echo "  ClusterRoleBindings: $crb_count"
        echo "  Cluster Groups: $cluster_group_count"
        
        echo -e "${BLUE}Namespace-scoped:${NC}"
        echo "  RoleBindings: $rb_count"
        echo "  Namespace Groups: $namespace_group_count"
        
        echo -e "${BLUE}Totals:${NC}"
        echo "  Total Groups: $total_group_count"
        echo "  Total Bindings: $((crb_count + rb_count))"
        
        # Mapping status
        if [ "$crb_count" -eq "$cluster_group_count" ] && [ "$crb_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Cluster mapping: Perfect${NC}"
        elif [ "$cluster_group_count" -gt 0 ]; then
            echo -e "${YELLOW}⚠️  Cluster mapping: Issues${NC}"
        fi
        
        if [ "$rb_count" -gt 0 ]; then
            echo -e "${GREEN}✅ Namespace mapping: Active${NC}"
        else
            echo -e "${YELLOW}ℹ️  No namespace resources${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}Current Groups:${NC}"
        cluster_groups=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | grep "cluster")
        namespace_groups=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | grep "ns")
        
        if [ ! -z "$cluster_groups" ]; then
            echo -e "  ${YELLOW}Cluster Groups:${NC}"
            echo "$cluster_groups" | awk '{print "    " $1}' | head -5
        fi
        
        if [ ! -z "$namespace_groups" ]; then
            echo -e "  ${YELLOW}Namespace Groups:${NC}"
            echo "$namespace_groups" | awk '{print "    " $1}' | head -5
        fi
        
        echo ""
        echo -e "${BLUE}Current Bindings:${NC}"
        cluster_bindings=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null)
        namespace_bindings=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null)
        
        if [ ! -z "$cluster_bindings" ]; then
            echo -e "  ${YELLOW}ClusterRoleBindings:${NC}"
            echo "$cluster_bindings" | awk '{print "    " $1}' | head -5
        fi
        
        if [ ! -z "$namespace_bindings" ]; then
            echo -e "  ${YELLOW}RoleBindings:${NC}"
            echo "$namespace_bindings" | awk '{print "    [" $1 "] " $2}' | head -5
            if [ "$rb_count" -gt 5 ]; then
                echo "    ... and $((rb_count-5)) more"
            fi
        fi
        
        # Check if user pressed Enter
        if read -t 5 -s; then
            echo -e "\n${GREEN}Returning to menu...${NC}"
            sleep 1
            break
        fi
    done
}

watch_pod_status() {
    echo -e "${YELLOW}Monitoring Kyverno pod status...${NC}"
    echo -e "${BLUE}Press Enter to return to menu (or auto-return in 30s)${NC}"
    echo ""
    
    # Show current status first
    kubectl get pods -n ${KYVERNO_NAMESPACE} -o wide
    echo ""
    echo "Watching for changes (press Enter to exit)..."
    
    # Start kubectl watch in background
    kubectl get pods -n ${KYVERNO_NAMESPACE} -w --no-headers 2>/dev/null &
    WATCH_PID=$!
    
    # Wait for user input or timeout (30 seconds)
    if read -t 30 -s; then
        echo -e "\n${GREEN}User requested return to menu...${NC}"
    else
        echo -e "\n${YELLOW}30-second timeout reached...${NC}"
    fi
    
    # Kill the watch process
    kill $WATCH_PID 2>/dev/null
    wait $WATCH_PID 2>/dev/null
    
    echo -e "${GREEN}Returning to menu...${NC}"
    sleep 1
}

run_health_check() {
    echo -e "${YELLOW}Running full health check...${NC}"
    echo ""
    if [ -f "./scripts/monitor-kyverno-rbac.sh" ]; then
        ./scripts/monitor-kyverno-rbac.sh
    else
        echo -e "${RED}Health check script not found!${NC}"
    fi
    echo ""
    echo -n "Press Enter to return to menu..."
    read
}

show_recent_activity() {
    echo -e "${YELLOW}Recent Activity Summary${NC}"
    echo -e "${BLUE}Generated at: $(date)${NC}"
    echo ""
    
    echo -e "${BLUE}=== Recent Generation Activity (last hour) ===${NC}"
    
    # Cluster-scoped generations
    cluster_generation_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --tail=100 --since=1h 2>/dev/null | grep "created generate target resource.*ClusterRoleBinding" | tail -5)
    
    # Namespace-scoped generations
    namespace_generation_logs=$(kubectl logs -n ${KYVERNO_NAMESPACE} -l app.kubernetes.io/component=background-controller --tail=100 --since=1h 2>/dev/null | grep "created generate target resource.*RoleBinding" | tail -10)
    
    if [ ! -z "$cluster_generation_logs" ]; then
        echo -e "  ${YELLOW}ClusterRoleBindings:${NC}"
        echo "$cluster_generation_logs" | while read line; do
            timestamp=$(echo "$line" | grep -o '^[0-9-]*T[0-9:]*Z')
            resource_name=$(echo "$line" | grep -o 'app-ocp-rbac[^[:space:]]*')
            echo -e "    ${GREEN}[$timestamp]${NC} $resource_name"
        done
    fi
    
    if [ ! -z "$namespace_generation_logs" ]; then
        echo -e "  ${YELLOW}RoleBindings:${NC}"
        echo "$namespace_generation_logs" | while read line; do
            timestamp=$(echo "$line" | grep -o '^[0-9-]*T[0-9:]*Z')
            namespace_info=$(echo "$line" | grep -o '/[^/]*/[^[:space:]]*-rb')
            echo -e "    ${GREEN}[$timestamp]${NC} $namespace_info"
        done
    fi
    
    if [ -z "$cluster_generation_logs" ] && [ -z "$namespace_generation_logs" ]; then
        echo -e "  ${YELLOW}No generation activity in the last hour${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}=== Policy Error History ===${NC}"
    
    # Get policy errors with proper timestamps
    policy_errors=$(kubectl get events --all-namespaces --field-selector reason=PolicyError -o json 2>/dev/null | jq -r ".items[] | select(.involvedObject.name == \"${CLUSTER_POLICY_NAME}\" or .involvedObject.name == \"${NAMESPACE_POLICY_NAME}\") | [.lastTimestamp, .message, .involvedObject.name] | @tsv" 2>/dev/null | sort -r | head -5)
    
    if [ ! -z "$policy_errors" ]; then
        echo "$policy_errors" | while IFS=$'\t' read -r timestamp message policy_name; do
            short_policy=$(echo "$policy_name" | sed 's/generate-//' | sed 's/-rolebindings//')
            echo -e "  ${RED}[$timestamp] [$short_policy]${NC} $(echo "$message" | cut -c1-60)..."
        done
        
        # Show time since last error
        latest_error=$(echo "$policy_errors" | head -1 | cut -f1)
        if [ ! -z "$latest_error" ]; then
            echo ""
            echo -e "  ${YELLOW}📅 Last error: $latest_error${NC}"
        fi
    else
        echo -e "  ${GREEN}✅ No policy errors found${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}=== Current Resource Summary ===${NC}"
    
    # Cluster-scoped resources
    crb_count=$(kubectl get clusterrolebindings -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l | tr -d ' ')
    cluster_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | grep -c "cluster" | tr -d ' ')
    
    # Namespace-scoped resources
    rb_count=$(kubectl get rolebindings -A -l app.kubernetes.io/managed-by=kyverno --no-headers 2>/dev/null | wc -l | tr -d ' ')
    namespace_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | grep -c "ns" | tr -d ' ')
    total_group_count=$(kubectl get groups.user.openshift.io --no-headers 2>/dev/null | grep "app-ocp-rbac" | wc -l | tr -d ' ')
    
    echo "  Cluster Resources:"
    echo "    ClusterRoleBindings: $crb_count"
    echo "    Cluster Groups: $cluster_group_count"
    
    echo "  Namespace Resources:"
    echo "    RoleBindings: $rb_count"
    echo "    Namespace Groups: $namespace_group_count"
    
    echo "  Totals:"
    echo "    Total Groups: $total_group_count"
    echo "    Total Bindings: $((crb_count + rb_count))"
    
    # Mapping status
    if [ "$crb_count" -eq "$cluster_group_count" ] && [ "$crb_count" -gt 0 ]; then
        echo -e "  ${GREEN}✅ Cluster mapping: Perfect${NC}"
    elif [ "$cluster_group_count" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️  Cluster mapping: Issues${NC}"
    fi
    
    if [ "$rb_count" -gt 0 ]; then
        echo -e "  ${GREEN}✅ Namespace resources: Active${NC}"
    else
        echo -e "  ${YELLOW}ℹ️  No namespace resources${NC}"
    fi
    
    echo ""
    echo -n "Press Enter to return to menu..."
    read
}

# Main loop
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            watch_generation_logs
            ;;
        2)
            watch_namespace_generation_logs
            ;;
        3)
            watch_policy_errors
            ;;
        4)
            watch_resource_counts
            ;;
        5)
            watch_pod_status
            ;;
        6)
            run_health_check
            ;;
        7)
            show_recent_activity
            ;;
        8)
            echo -e "${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            sleep 2
            ;;
    esac
done
