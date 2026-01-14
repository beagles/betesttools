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

    # A records from simple.sh with expected values
    check_record_value "$dns_server" "www.example.com" "A" "A record (multi-value)" "192.168.1.10" "192.168.1.11"
    check_record_value "$dns_server" "web.example.com" "A" "A record (multi-value)" "10.0.0.10" "10.0.0.11" "10.0.0.12"
    check_record_value "$dns_server" "db1.example.com" "A" "A record" "192.168.2.20"
    check_record_value "$dns_server" "db2.example.com" "A" "A record" "192.168.2.21"
    check_record_value "$dns_server" "api.example.com" "A" "A record (multi-value)" "172.16.0.30" "172.16.0.31"
    check_record_value "$dns_server" "www.test.org" "A" "A record" "203.0.113.10"
    check_record_value "$dns_server" "app.test.org" "A" "A record (multi-value)" "203.0.113.20" "203.0.113.21"
    check_record_value "$dns_server" "cache.test.org" "A" "A record (multi-value)" "10.1.1.50" "10.1.1.51"
    check_record_value "$dns_server" "v1.api.dev" "A" "A record" "192.168.10.100"
    check_record_value "$dns_server" "v2.api.dev" "A" "A record" "192.168.10.101"
    check_record_value "$dns_server" "staging.api.dev" "A" "A record" "192.168.10.200"
    check_record_value "$dns_server" "frontend.webapp.io" "A" "A record (multi-value)" "198.51.100.10" "198.51.100.11"
    check_record_value "$dns_server" "backend.webapp.io" "A" "A record" "198.51.100.20"
    check_record_value "$dns_server" "api.service.net" "A" "A record" "172.20.0.10"
    check_record_value "$dns_server" "web.service.net" "A" "A record (multi-value)" "172.20.0.20" "172.20.0.21"
}

check_aaaa_records() {
    local dns_server=$1

    print_info "Checking AAAA records..."

    # AAAA records from simple.sh with expected IPv6 values
    check_record_value "$dns_server" "www.example.com" "AAAA" "AAAA record (multi-value)" "2001:db8::1" "2001:db8::2"
    check_record_value "$dns_server" "web.example.com" "AAAA" "AAAA record" "2001:db8::10"
    check_record_value "$dns_server" "www.test.org" "AAAA" "AAAA record" "2001:db8:1::1"
    check_record_value "$dns_server" "v1.api.dev" "AAAA" "AAAA record" "2001:db8:2::100"
    check_record_value "$dns_server" "frontend.webapp.io" "AAAA" "AAAA record (multi-value)" "2001:db8:3::10" "2001:db8:3::11"
    check_record_value "$dns_server" "api.service.net" "AAAA" "AAAA record" "2001:db8:4::10"
}

check_cname_records() {
    local dns_server=$1

    print_info "Checking CNAME records..."

    # CNAME records from simple.sh with expected targets
    check_record_value "$dns_server" "blog.example.com" "CNAME" "CNAME record" "www.example.com."
    check_record_value "$dns_server" "shop.example.com" "CNAME" "CNAME record" "web.example.com."
    check_record_value "$dns_server" "docs.example.com" "CNAME" "CNAME record" "www.example.com."
    check_record_value "$dns_server" "mail.test.org" "CNAME" "CNAME record" "www.test.org."
    check_record_value "$dns_server" "ftp.test.org" "CNAME" "CNAME record" "www.test.org."
    check_record_value "$dns_server" "latest.api.dev" "CNAME" "CNAME record" "v2.api.dev."
    check_record_value "$dns_server" "app.webapp.io" "CNAME" "CNAME record" "frontend.webapp.io."
    check_record_value "$dns_server" "portal.service.net" "CNAME" "CNAME record" "web.service.net."
}

check_mx_records() {
    local dns_server=$1

    print_info "Checking MX records..."

    # MX records from simple.sh (zone apex) with expected priorities and hosts
    check_record_value "$dns_server" "example.com" "MX" "MX record (multi-value)" "10 mail1.example.com." "20 mail2.example.com."
    check_record_value "$dns_server" "test.org" "MX" "MX record (multi-value)" "10 mx1.test.org." "20 mx2.test.org."
    check_record_value "$dns_server" "webapp.io" "MX" "MX record" "5 mail.webapp.io."
    check_record_value "$dns_server" "partner.com" "MX" "MX record" "10 mail.partner.com."
}

check_txt_records() {
    local dns_server=$1

    print_info "Checking TXT records..."

    # TXT records from simple.sh with expected content
    check_record_value "$dns_server" "example.com" "TXT" "TXT record (SPF)" "v=spf1 mx -all"
    check_record_value "$dns_server" "_dmarc.example.com" "TXT" "TXT record (DMARC)" "v=DMARC1" "p=quarantine"
    check_record_value "$dns_server" "verification.example.com" "TXT" "TXT record" "google-site-verification=abc123def456"
    check_record_value "$dns_server" "test.org" "TXT" "TXT record (SPF)" "v=spf1" "_spf.google.com"
    check_record_value "$dns_server" "webapp.io" "TXT" "TXT record (SPF)" "v=spf1 mx a -all"
}

check_srv_records() {
    local dns_server=$1

    print_info "Checking SRV records..."

    # SRV records from simple.sh with expected priority, weight, port, target
    check_record_value "$dns_server" "_sip._tcp.example.com" "SRV" "SRV record (SIP)" "10 60 5060 sipserver.example.com."
    check_record_value "$dns_server" "_xmpp._tcp.example.com" "SRV" "SRV record (XMPP)" "5 30 5222 xmpp.example.com."
    check_record_value "$dns_server" "_ldap._tcp.test.org" "SRV" "SRV record (LDAP)" "10 100 389 ldap.test.org."
    check_record_value "$dns_server" "_http._tcp.service.net" "SRV" "SRV record (HTTP)" "10 50 80 web.service.net."
}

check_soa_records() {
    local dns_server=$1

    print_info "Checking SOA records..."

    # Check SOA for main zones - we just verify they exist and contain expected email
    check_record_value "$dns_server" "example.com" "SOA" "SOA record" "admin.example.com"
    check_record_value "$dns_server" "test.org" "SOA" "SOA record" "hostmaster.test.org"
    check_record_value "$dns_server" "api.dev" "SOA" "SOA record" "devops.api.dev"
    check_record_value "$dns_server" "webapp.io" "SOA" "SOA record" "admin.webapp.io"
    check_record_value "$dns_server" "myapp.cloud" "SOA" "SOA record" "ops.myapp.cloud"
    check_record_value "$dns_server" "service.net" "SOA" "SOA record" "admin.service.net"
}

check_ns_records() {
    local dns_server=$1

    print_info "Checking NS records..."

    # Check NS records exist for main zones (values are deployment-specific)
    # We just verify the query returns something
    local zones=("example.com" "test.org" "api.dev" "webapp.io")

    for zone in "${zones[@]}"; do
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
