#!/bin/bash
#
# OpenStack Designate Test Data Verification Script
#
# This script verifies that all resources created by simple.sh are present
# in the OpenStack Designate deployment. It performs read-only checks and
# reports which resources are found and which are missing.
#
# Requirements:
# - OpenStack CLI (python-openstackclient) installed
# - Authenticated with OpenStack credentials
# - Designate service available
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

os=openstack
VERBOSE=${VERBOSE:-false}

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# Counters for summary
declare -A FOUND_COUNT
declare -A MISSING_COUNT

# ============================================================================
# Helper Functions
# ============================================================================

print_section() {
    echo -e "\n${BOLD}${CYAN}===================================================${NC}"
    echo -e "${BOLD}${CYAN}$1${NC}"
    echo -e "${BOLD}${CYAN}===================================================${NC}\n"
}

print_found() {
    echo -e "${GREEN}✓${NC} $1"
}

print_missing() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Get project ID by name
get_project_id() {
    local project_name=$1
    $os project show "$project_name" -c id -f value 2>/dev/null || echo ""
}

# Check if resource exists in list
resource_exists() {
    local list=$1
    local name=$2
    [[ $list == *"$name"* ]]
}

# Increment found counter
count_found() {
    local resource_type=$1
    FOUND_COUNT[$resource_type]=$((${FOUND_COUNT[$resource_type]:-0} + 1))
}

# Increment missing counter
count_missing() {
    local resource_type=$1
    MISSING_COUNT[$resource_type]=$((${MISSING_COUNT[$resource_type]:-0} + 1))
}

# ============================================================================
# TLD Verification
# ============================================================================

check_tlds() {
    print_section "Checking TLDs"

    local existing_tlds=$($os tld list -c name -f value 2>/dev/null || echo "")

    for tld in "${TLDS[@]}"; do
        if resource_exists "$existing_tlds" "$tld"; then
            print_found "TLD exists: $tld"
            count_found "tlds"
        else
            print_missing "TLD missing: $tld"
            count_missing "tlds"
        fi
    done
}

# ============================================================================
# Project Verification
# ============================================================================

check_projects() {
    print_section "Checking Projects"

    local existing_projects=$($os project list -c Name -f value 2>/dev/null || echo "")

    for project_info in "${PROJECTS[@]}"; do
        IFS=':' read -r project_name project_desc <<< "$project_info"

        if resource_exists "$existing_projects" "$project_name"; then
            local project_id=$(get_project_id "$project_name")
            print_found "Project exists: $project_name (ID: $project_id)"
            count_found "projects"
        else
            print_missing "Project missing: $project_name"
            count_missing "projects"
        fi
    done
}

# ============================================================================
# User and Role Verification
# ============================================================================

check_users() {
    print_section "Checking Users and Role Assignments"

    local existing_users=$($os user list -c Name -f value 2>/dev/null || echo "")

    for user_info in "${USERS[@]}"; do
        IFS=':' read -r username password project_name <<< "$user_info"

        # Check if user exists
        if resource_exists "$existing_users" "$username"; then
            print_found "User exists: $username"
            count_found "users"

            # Check if admin role is assigned
            local role_assignments=$($os role assignment list --user "$username" --project "$project_name" --names -c Role -f value 2>/dev/null || echo "")

            if resource_exists "$role_assignments" "admin"; then
                print_found "Admin role assigned: $username on $project_name"
                count_found "role_assignments"
            else
                print_missing "Admin role not assigned: $username on $project_name"
                count_missing "role_assignments"
            fi
        else
            print_missing "User missing: $username"
            count_missing "users"
            count_missing "role_assignments"
        fi
    done
}

# ============================================================================
# Quota Verification
# ============================================================================

check_quotas() {
    print_section "Checking Project Quotas"

    for quota_config in "${QUOTAS[@]}"; do
        IFS=':' read -r project_name zones zone_recordsets zone_records recordset_records <<< "$quota_config"

        local project_id=$(get_project_id "$project_name")
        if [[ -z "$project_id" ]]; then
            print_warning "Project not found, skipping quota check: $project_name"
            continue
        fi

        # Get current quotas
        local current_quotas=$($os dns quota list --project-id "$project_id" -f value 2>/dev/null || echo "")

        if [[ -n "$current_quotas" ]]; then
            # Extract quota values
            local actual_zones=$(echo "$current_quotas" | grep "^zones" | awk '{print $2}')
            local actual_recordsets=$(echo "$current_quotas" | grep "^zone_recordsets" | awk '{print $2}')

            if [[ "$actual_zones" == "$zones" && "$actual_recordsets" == "$zone_recordsets" ]]; then
                print_found "Quotas configured for $project_name (zones:$zones, recordsets:$zone_recordsets)"
                count_found "quotas"
            else
                print_missing "Quotas mismatch for $project_name (expected zones:$zones, got:$actual_zones)"
                count_missing "quotas"
            fi
        else
            print_missing "Quotas not set for: $project_name"
            count_missing "quotas"
        fi
    done
}

# ============================================================================
# Blacklist Verification
# ============================================================================

check_blacklists() {
    print_section "Checking Blacklists"

    local existing_blacklists=$($os zone blacklist list -c pattern -f value 2>/dev/null || echo "")

    for blacklist_info in "${BLACKLISTS[@]}"; do
        IFS=':' read -r pattern description <<< "$blacklist_info"

        if resource_exists "$existing_blacklists" "$pattern"; then
            print_found "Blacklist exists: $pattern"
            count_found "blacklists"
        else
            print_missing "Blacklist missing: $pattern"
            count_missing "blacklists"
        fi
    done
}

# ============================================================================
# Zone Verification
# ============================================================================

check_zones() {
    print_section "Checking DNS Zones"

    local existing_zones=$($os zone list --all-projects -c name -f value 2>/dev/null || echo "")

    for zone_info in "${ZONES[@]}"; do
        IFS=':' read -r project_name zone_name email ttl description <<< "$zone_info"

        if resource_exists "$existing_zones" "$zone_name"; then
            print_found "Zone exists: $zone_name (project: $project_name)"
            count_found "zones"
        else
            print_missing "Zone missing: $zone_name (project: $project_name)"
            count_missing "zones"
        fi
    done
}

# ============================================================================
# Recordset Verification
# ============================================================================

check_recordsets() {
    print_section "Checking DNS Recordsets"

    print_info "Checking sample A records..."
    check_sample_a_records

    print_info "Checking sample AAAA records..."
    check_sample_aaaa_records

    print_info "Checking sample CNAME records..."
    check_sample_cname_records

    print_info "Checking sample MX records..."
    check_sample_mx_records

    print_info "Checking sample TXT records..."
    check_sample_txt_records

    print_info "Checking sample SRV records..."
    check_sample_srv_records
}

check_sample_a_records() {
    # Check a representative sample of A records
    local sample_records=(
        "example.com.:www.example.com."
        "example.com.:web.example.com."
        "test.org.:www.test.org."
        "api.dev.:v1.api.dev."
        "webapp.io.:frontend.webapp.io."
    )

    for record_info in "${sample_records[@]}"; do
        IFS=':' read -r zone record_fqdn <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")

        if resource_exists "$existing_records" "$record_fqdn"; then
            print_found "A record exists: $record_fqdn"
            count_found "recordsets"
        else
            print_missing "A record missing: $record_fqdn"
            count_missing "recordsets"
        fi
    done
}

check_sample_aaaa_records() {
    # Check sample AAAA records
    local sample_records=(
        "example.com.:www.example.com."
        "test.org.:www.test.org."
        "api.dev.:v1.api.dev."
    )

    for record_info in "${sample_records[@]}"; do
        IFS='#' read -r zone record_fqdn <<< "$record_info"

        # Check if recordset exists and has AAAA type
        local recordset_info=$($os recordset show "$zone" "$record_fqdn" -c type -c records -f value 2>/dev/null || echo "")

        if [[ $recordset_info == *"AAAA"* ]]; then
            print_found "AAAA record exists: $record_fqdn"
            count_found "recordsets"
        else
            # Don't count as missing if the A record exists but no AAAA
            if [[ -n "$recordset_info" ]]; then
                print_info "AAAA record not set for: $record_fqdn (A record exists)"
            fi
        fi
    done
}

check_sample_cname_records() {
    # Check sample CNAME records
    local sample_records=(
        "example.com.:blog.example.com."
        "example.com.:shop.example.com."
        "test.org.:mail.test.org."
    )

    for record_info in "${sample_records[@]}"; do
        IFS=':' read -r zone record_fqdn <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")

        if resource_exists "$existing_records" "$record_fqdn"; then
            print_found "CNAME record exists: $record_fqdn"
            count_found "recordsets"
        else
            print_missing "CNAME record missing: $record_fqdn"
            count_missing "recordsets"
        fi
    done
}

check_sample_mx_records() {
    # Check MX records at zone apex
    local sample_zones=("example.com." "test.org." "webapp.io.")

    for zone in "${sample_zones[@]}"; do
        local recordset_info=$($os recordset show "$zone" "$zone" -c type -f value 2>/dev/null || echo "")

        if [[ $recordset_info == *"MX"* ]]; then
            print_found "MX record exists for: $zone"
            count_found "recordsets"
        else
            print_missing "MX record missing for: $zone"
            count_missing "recordsets"
        fi
    done
}

check_sample_txt_records() {
    # Check sample TXT records
    local sample_records=(
        "example.com.:example.com."
        "example.com.:_dmarc.example.com."
        "test.org.:test.org."
    )

    for record_info in "${sample_records[@]}"; do
        IFS=':' read -r zone record_fqdn <<< "$record_info"

        local recordset_info=$($os recordset show "$zone" "$record_fqdn" -c type -f value 2>/dev/null || echo "")

        if [[ $recordset_info == *"TXT"* ]]; then
            print_found "TXT record exists: $record_fqdn"
            count_found "recordsets"
        else
            # Don't count as missing if another record type exists at that name
            if [[ -n "$recordset_info" ]]; then
                print_info "TXT record not set for: $record_fqdn (other record type exists)"
            fi
        fi
    done
}

check_sample_srv_records() {
    # Check sample SRV records
    local sample_records=(
        "example.com.:_sip._tcp.example.com."
        "example.com.:_xmpp._tcp.example.com."
        "test.org.:_ldap._tcp.test.org."
    )

    for record_info in "${sample_records[@]}"; do
        IFS=':' read -r zone record_fqdn <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")

        if resource_exists "$existing_records" "$record_fqdn"; then
            print_found "SRV record exists: $record_fqdn"
            count_found "recordsets"
        else
            print_missing "SRV record missing: $record_fqdn"
            count_missing "recordsets"
        fi
    done
}

# ============================================================================
# PTR Record Verification
# ============================================================================

check_ptr_records() {
    print_section "Checking PTR Records (Reverse DNS)"

    print_info "Checking for PTR records..."

    # Try to list PTR records
    local ptr_records=$($os ptr record list -c id -c ptrdname -f value 2>/dev/null || echo "")

    if [[ -n "$ptr_records" ]]; then
        local ptr_count=$(echo "$ptr_records" | wc -l)
        print_found "Found $ptr_count PTR record(s)"
        count_found "ptr_records"

        # Show the PTR records
        while IFS= read -r line; do
            local ptr_id=$(echo "$line" | awk '{print $1}')
            local ptr_name=$(echo "$line" | awk '{print $2}')
            print_info "  PTR: $ptr_id -> $ptr_name"
        done <<< "$ptr_records"
    else
        print_info "No PTR records found (this is normal if no floating IPs exist)"
    fi
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
    print_section "Verification Summary"

    local total_found=0
    local total_missing=0

    echo -e "${BOLD}Resources Found:${NC}"
    for resource_type in "${!FOUND_COUNT[@]}"; do
        local count=${FOUND_COUNT[$resource_type]}
        echo -e "  ${GREEN}${resource_type}:${NC} $count"
        ((total_found += count))
    done

    echo ""
    echo -e "${BOLD}Resources Missing:${NC}"
    if [[ ${#MISSING_COUNT[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}None - all resources found!${NC}"
    else
        for resource_type in "${!MISSING_COUNT[@]}"; do
            local count=${MISSING_COUNT[$resource_type]}
            echo -e "  ${RED}${resource_type}:${NC} $count"
            ((total_missing += count))
        done
    fi

    echo ""
    echo -e "${BOLD}Overall Status:${NC}"
    echo -e "  Total Found: ${GREEN}$total_found${NC}"
    echo -e "  Total Missing: ${RED}$total_missing${NC}"

    echo ""
    if [[ $total_missing -eq 0 ]]; then
        print_found "All expected resources are present!"
    else
        print_warning "Some resources are missing. You may need to run simple.sh to create them."
        echo ""
        print_info "To create missing resources, run:"
        print_info "  ./designate/populate-data/simple.sh"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo -e "${BOLD}${CYAN}"
    echo "============================================================"
    echo "  OpenStack Designate Test Data Verification Script"
    echo "============================================================"
    echo -e "${NC}"

    # Check if OpenStack CLI is available
    if ! command -v $os &> /dev/null; then
        print_missing "OpenStack CLI not found. Please install python-openstackclient."
        exit 1
    fi

    # Check if we have valid credentials
    if ! $os token issue >/dev/null 2>&1; then
        print_missing "Not authenticated with OpenStack. Please source your credentials file."
        exit 1
    fi

    print_found "OpenStack CLI found and authenticated"

    # Execute all verification functions
    check_tlds
    check_projects
    check_users
    check_quotas
    check_blacklists
    check_zones
    check_recordsets
    check_ptr_records

    # Print summary
    print_summary
}

# Run main function
main
