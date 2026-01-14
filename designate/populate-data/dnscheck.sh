#!/bin/bash
#
# DNS Server Verification Script using dig
#
# This script uses 'dig' to query DNS servers and verify that records
# created by simple.sh are being served correctly with the expected values.
# This validates that the Designate backend DNS servers are properly
# configured and serving the zones with correct data.
#
# Usage:
#   ./dnscheck.sh <dns-server-ip1> [dns-server-ip2] [dns-server-ip3] ...
#
# Example:
#   ./dnscheck.sh 192.168.1.10 192.168.1.11
#   ./dnscheck.sh 10.0.0.53
#
# Requirements:
# - dig command (from bind-utils or dnsutils package)
#

set -e  # Exit on error

# ============================================================================
# Load Test Data
# ============================================================================

# Source common test data definitions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/testdata.sh"

# ============================================================================
# Configuration
# ============================================================================

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# Counters for summary
declare -A SUCCESS_COUNT
declare -A FAILURE_COUNT
declare -A DNS_SERVER_STATS

# ============================================================================
# Helper Functions
# ============================================================================

print_section() {
    echo -e "\n${BOLD}${CYAN}===================================================${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}===================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_failure() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Increment success counter
count_success() {
    local dns_server=$1
    local record_type=$2
    SUCCESS_COUNT["${dns_server}:${record_type}"]=$((${SUCCESS_COUNT["${dns_server}:${record_type}"]:-0} + 1))
    DNS_SERVER_STATS["${dns_server}:success"]=$((${DNS_SERVER_STATS["${dns_server}:success"]:-0} + 1))
}

# Increment failure counter
count_failure() {
    local dns_server=$1
    local record_type=$2
    FAILURE_COUNT["${dns_server}:${record_type}"]=$((${FAILURE_COUNT["${dns_server}:${record_type}"]:-0} + 1))
    DNS_SERVER_STATS["${dns_server}:failure"]=$((${DNS_SERVER_STATS["${dns_server}:failure"]:-0} + 1))
}

# Query DNS server with dig
query_dns() {
    local dns_server=$1
    local query_name=$2
    local record_type=$3
    local timeout=${4:-2}

    dig @"$dns_server" "$query_name" "$record_type" +short +time="$timeout" +tries=2 2>/dev/null
}

# Check if expected value(s) are present in actual result
# For multi-value records, all expected values must be present (order doesn't matter)
value_matches() {
    local actual=$1
    shift
    local expected=("$@")

    # If no response, fail
    if [[ -z "$actual" ]]; then
        return 1
    fi

    # Check each expected value
    for exp_value in "${expected[@]}"; do
        if [[ ! "$actual" =~ $exp_value ]]; then
            return 1
        fi
    done

    return 0
}

# Check if a DNS query returns expected results
check_record_value() {
    local dns_server=$1
    local query_name=$2
    local record_type=$3
    local description=$4
    shift 4
    local expected_values=("$@")

    local result=$(query_dns "$dns_server" "$query_name" "$record_type")

    if [[ -z "$result" ]]; then
        print_failure "$description: $query_name ($record_type) - No response"
        count_failure "$dns_server" "$record_type"
        return 1
    fi

    # Check if expected values match
    if value_matches "$result" "${expected_values[@]}"; then
        # Truncate output for readability
        local display_result=$(echo "$result" | tr '\n' ' ' | head -c 80)
        print_success "$description: $query_name ($record_type) -> $display_result"
        count_success "$dns_server" "$record_type"
        return 0
    else
        # Show what we got vs what we expected
        local display_result=$(echo "$result" | tr '\n' ' ' | head -c 60)
        print_failure "$description: $query_name ($record_type)"
        print_failure "  Expected: ${expected_values[*]}"
        print_failure "  Got: $display_result"
        count_failure "$dns_server" "$record_type"
        return 1
    fi
}

# ============================================================================
# DNS Record Checks
# ============================================================================

check_a_records() {
    local dns_server=$1

    print_info "Checking A records..."

    # Check all A records from testdata.sh
    for record_info in "${A_RECORDS[@]}"; do
        IFS=':' read -r zone name ip1 ip2 ip3 <<< "$record_info"
        local fqdn="${name}.${zone}"

        # Build expected values array
        local expected_values=()
        [[ -n "$ip1" ]] && expected_values+=("$ip1")
        [[ -n "$ip2" ]] && expected_values+=("$ip2")
        [[ -n "$ip3" ]] && expected_values+=("$ip3")

        # Determine description based on number of values
        local desc="A record"
        [[ ${#expected_values[@]} -gt 1 ]] && desc="A record (multi-value)"

        check_record_value "$dns_server" "$fqdn" "A" "$desc" "${expected_values[@]}"
    done
}

check_aaaa_records() {
    local dns_server=$1

    print_info "Checking AAAA records..."

    # Check all AAAA records from testdata.sh
    for record_info in "${AAAA_RECORDS[@]}"; do
        IFS=':' read -r zone name ip1 ip2 <<< "$record_info"
        local fqdn="${name}.${zone}"

        # Build expected values array
        local expected_values=()
        [[ -n "$ip1" ]] && expected_values+=("$ip1")
        [[ -n "$ip2" ]] && expected_values+=("$ip2")

        # Determine description based on number of values
        local desc="AAAA record"
        [[ ${#expected_values[@]} -gt 1 ]] && desc="AAAA record (multi-value)"

        check_record_value "$dns_server" "$fqdn" "AAAA" "$desc" "${expected_values[@]}"
    done
}

check_cname_records() {
    local dns_server=$1

    print_info "Checking CNAME records..."

    # Check all CNAME records from testdata.sh
    for record_info in "${CNAME_RECORDS[@]}"; do
        IFS=':' read -r zone name target <<< "$record_info"
        local fqdn="${name}.${zone}"

        check_record_value "$dns_server" "$fqdn" "CNAME" "CNAME record" "$target"
    done
}

check_mx_records() {
    local dns_server=$1

    print_info "Checking MX records..."

    # Check all MX records from testdata.sh
    for record_info in "${MX_RECORDS[@]}"; do
        IFS=':' read -r zone pri1 host1 pri2 host2 <<< "$record_info"

        # Build expected values array
        local expected_values=()
        [[ -n "$pri1" && -n "$host1" ]] && expected_values+=("$pri1 $host1")
        [[ -n "$pri2" && -n "$host2" ]] && expected_values+=("$pri2 $host2")

        # Determine description based on number of values
        local desc="MX record"
        [[ ${#expected_values[@]} -gt 1 ]] && desc="MX record (multi-value)"

        check_record_value "$dns_server" "$zone" "MX" "$desc" "${expected_values[@]}"
    done
}

check_txt_records() {
    local dns_server=$1

    print_info "Checking TXT records..."

    # Check all TXT records from testdata.sh
    for record_info in "${TXT_RECORDS[@]}"; do
        IFS=':' read -r zone name value <<< "$record_info"

        local query_name
        if [[ "$name" == "@" ]]; then
            query_name="$zone"
        else
            query_name="${name}.${zone}"
        fi

        # Determine description based on content
        local desc="TXT record"
        [[ "$value" == v=spf1* ]] && desc="TXT record (SPF)"
        [[ "$value" == v=DMARC1* ]] && desc="TXT record (DMARC)"

        # For TXT records, we check if the expected value is contained in the response
        # since TXT records may have quotes or be split
        check_record_value "$dns_server" "$query_name" "TXT" "$desc" "$value"
    done
}

check_srv_records() {
    local dns_server=$1

    print_info "Checking SRV records..."

    # Check all SRV records from testdata.sh
    for record_info in "${SRV_RECORDS[@]}"; do
        IFS=':' read -r zone name priority weight port target <<< "$record_info"
        local fqdn="${name}.${zone}"

        local srv_value="$priority $weight $port $target"

        # Determine description based on service
        local desc="SRV record"
        [[ "$name" == *sip* ]] && desc="SRV record (SIP)"
        [[ "$name" == *xmpp* ]] && desc="SRV record (XMPP)"
        [[ "$name" == *ldap* ]] && desc="SRV record (LDAP)"
        [[ "$name" == *http* ]] && desc="SRV record (HTTP)"

        check_record_value "$dns_server" "$fqdn" "SRV" "$desc" "$srv_value"
    done
}

check_soa_records() {
    local dns_server=$1

    print_info "Checking SOA records..."

    # Check SOA records for all zones - verify they exist and contain expected email
    for zone_info in "${ZONES[@]}"; do
        IFS=':' read -r project zone email ttl description <<< "$zone_info"

        # Convert email format: admin@example.com -> admin.example.com
        local soa_email=$(echo "$email" | sed 's/@/./')

        check_record_value "$dns_server" "$zone" "SOA" "SOA record" "$soa_email"
    done
}

check_ns_records() {
    local dns_server=$1

    print_info "Checking NS records..."

    # Check NS records exist for all zones (values are deployment-specific)
    # We just verify the query returns something
    for zone_info in "${ZONES[@]}"; do
        IFS=':' read -r project zone email ttl description <<< "$zone_info"

        local result=$(query_dns "$dns_server" "$zone" "NS")

        if [[ -n "$result" ]]; then
            local display_result=$(echo "$result" | tr '\n' ' ' | head -c 60)
            print_success "NS record: $zone (NS) -> $display_result"
            count_success "$dns_server" "NS"
        else
            print_failure "NS record: $zone (NS) - No response"
            count_failure "$dns_server" "NS"
        fi
    done
}

# ============================================================================
# Main Verification Function
# ============================================================================

verify_dns_server() {
    local dns_server=$1

    print_section "Checking DNS Server: $dns_server"

    # Test if DNS server is reachable
    print_info "Testing DNS server connectivity..."
    local test_result=$(query_dns "$dns_server" "." "NS" 2)

    if [[ -z "$test_result" ]]; then
        print_failure "DNS server $dns_server is not responding"
        return 1
    fi

    print_success "DNS server $dns_server is responding"
    echo ""

    # Run all checks
    check_soa_records "$dns_server"
    echo ""

    check_ns_records "$dns_server"
    echo ""

    check_a_records "$dns_server"
    echo ""

    check_aaaa_records "$dns_server"
    echo ""

    check_cname_records "$dns_server"
    echo ""

    check_mx_records "$dns_server"
    echo ""

    check_txt_records "$dns_server"
    echo ""

    check_srv_records "$dns_server"
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
    local dns_servers=("$@")

    print_section "DNS Verification Summary"

    echo -e "${BOLD}Results by DNS Server:${NC}"
    for dns_server in "${dns_servers[@]}"; do
        local success=${DNS_SERVER_STATS["${dns_server}:success"]:-0}
        local failure=${DNS_SERVER_STATS["${dns_server}:failure"]:-0}
        local total=$((success + failure))

        if [[ $total -gt 0 ]]; then
            local success_pct=$((success * 100 / total))
            echo -e "  ${BOLD}$dns_server${NC}:"
            echo -e "    ${GREEN}Successful queries:${NC} $success"
            echo -e "    ${RED}Failed queries:${NC} $failure"
            echo -e "    Success rate: ${success_pct}%"
        else
            echo -e "  ${BOLD}$dns_server${NC}:"
            echo -e "    ${RED}No successful queries${NC}"
        fi
        echo ""
    done

    echo -e "${BOLD}Results by Record Type (all servers):${NC}"
    declare -A type_success
    declare -A type_failure

    # Aggregate by record type
    for key in "${!SUCCESS_COUNT[@]}"; do
        local record_type="${key#*:}"
        type_success["$record_type"]=$((${type_success["$record_type"]:-0} + ${SUCCESS_COUNT["$key"]}))
    done

    for key in "${!FAILURE_COUNT[@]}"; do
        local record_type="${key#*:}"
        type_failure["$record_type"]=$((${type_failure["$record_type"]:-0} + ${FAILURE_COUNT["$key"]}))
    done

    # Display aggregated results
    for record_type in A AAAA CNAME MX TXT SRV SOA NS; do
        local success=${type_success["$record_type"]:-0}
        local failure=${type_failure["$record_type"]:-0}

        if [[ $success -gt 0 || $failure -gt 0 ]]; then
            echo -e "  ${BOLD}$record_type records:${NC} ${GREEN}$success success${NC} / ${RED}$failure failed${NC}"
        fi
    done

    echo ""

    # Overall status
    local total_success=0
    local total_failure=0

    for dns_server in "${dns_servers[@]}"; do
        total_success=$((total_success + ${DNS_SERVER_STATS["${dns_server}:success"]:-0}))
        total_failure=$((total_failure + ${DNS_SERVER_STATS["${dns_server}:failure"]:-0}))
    done

    local grand_total=$((total_success + total_failure))

    if [[ $grand_total -gt 0 ]]; then
        local overall_pct=$((total_success * 100 / grand_total))
        echo -e "${BOLD}Overall Status:${NC}"
        echo -e "  Total queries: $grand_total"
        echo -e "  ${GREEN}Successful: $total_success${NC}"
        echo -e "  ${RED}Failed: $total_failure${NC}"
        echo -e "  Overall success rate: ${overall_pct}%"

        echo ""
        if [[ $total_failure -eq 0 ]]; then
            print_success "All DNS queries returned correct values!"
        elif [[ $overall_pct -ge 80 ]]; then
            print_warning "Most DNS queries successful, but some failures or mismatches detected."
        else
            print_failure "Many DNS queries failed or returned incorrect values. Check DNS server configuration."
        fi
    fi
}

# ============================================================================
# Usage Information
# ============================================================================

usage() {
    echo -e "${BOLD}Usage:${NC}"
    echo "  $0 <dns-server-ip1> [dns-server-ip2] [dns-server-ip3] ..."
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 192.168.1.10"
    echo "  $0 192.168.1.10 192.168.1.11"
    echo "  $0 10.0.0.53 10.0.0.54 10.0.0.55"
    echo ""
    echo -e "${BOLD}Description:${NC}"
    echo "  This script uses 'dig' to verify that DNS records created by simple.sh"
    echo "  are being served correctly with the expected values by the specified DNS servers."
    echo ""
    echo -e "${BOLD}Requirements:${NC}"
    echo "  - dig command (install with: yum install bind-utils  OR  apt install dnsutils)"
    echo ""
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo -e "${BOLD}${CYAN}"
    echo "============================================================"
    echo "  DNS Server Value Verification Script (using dig)"
    echo "============================================================"
    echo -e "${NC}"

    # Check arguments
    if [[ $# -eq 0 ]]; then
        print_failure "No DNS servers specified"
        echo ""
        usage
        exit 1
    fi

    # Check if dig is installed
    if ! command -v dig &> /dev/null; then
        print_failure "dig command not found"
        echo ""
        print_info "Install dig with one of these commands:"
        print_info "  RHEL/CentOS/Rocky: sudo yum install bind-utils"
        print_info "  Debian/Ubuntu: sudo apt install dnsutils"
        print_info "  Alpine: apk add bind-tools"
        exit 1
    fi

    print_success "dig command found"

    # Store DNS servers
    dns_servers=("$@")

    print_info "Will check ${#dns_servers[@]} DNS server(s): ${dns_servers[*]}"
    print_info "Verifying both existence and correctness of DNS record values"

    # Verify each DNS server
    for dns_server in "${dns_servers[@]}"; do
        verify_dns_server "$dns_server"
    done

    # Print summary
    print_summary "${dns_servers[@]}"
}

# Run main function with all arguments
main "$@"
