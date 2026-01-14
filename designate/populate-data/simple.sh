#!/bin/bash
#
# OpenStack Designate Test Data Population Script
#
# This script populates an OpenStack Designate deployment with comprehensive
# test data including TLDs, projects, zones, recordsets, quotas, and more.
# It is idempotent and safe to run multiple times.
#
# Requirements:
# - OpenStack CLI (python-openstackclient) installed
# - Authenticated with admin credentials
# - Designate service available and configured
#

set -e  # Exit on error

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
declare -A CREATED_COUNT
declare -A SKIPPED_COUNT

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

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
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

# Increment created counter
count_created() {
    local resource_type=$1
    CREATED_COUNT[$resource_type]=$((${CREATED_COUNT[$resource_type]:-0} + 1))
}

# Increment skipped counter
count_skipped() {
    local resource_type=$1
    SKIPPED_COUNT[$resource_type]=$((${SKIPPED_COUNT[$resource_type]:-0} + 1))
}

# ============================================================================
# TLD Creation
# ============================================================================

create_tlds() {
    print_section "Creating TLDs"

    local tlds=("com" "org" "net" "edu" "io" "dev" "cloud" "local")
    local existing_tlds=$($os tld list -c name -f value 2>/dev/null || echo "")

    for tld in "${tlds[@]}"; do
        if resource_exists "$existing_tlds" "$tld"; then
            print_info "TLD already exists: $tld"
            count_skipped "tlds"
        else
            if $os tld create --name "$tld" --description "Test TLD: $tld" >/dev/null 2>&1; then
                print_success "Created TLD: $tld"
                count_created "tlds"
            else
                print_error "Failed to create TLD: $tld"
            fi
        fi
    done
}

# ============================================================================
# Project Creation
# ============================================================================

create_projects() {
    print_section "Creating Projects"

    local projects=(
        "project1:Primary testing project"
        "project2:Secondary testing project"
        "project3:Zone sharing recipient project"
        "admin-project:Administrative testing project"
    )

    local existing_projects=$($os project list -c Name -f value 2>/dev/null || echo "")

    for project_info in "${projects[@]}"; do
        IFS=':' read -r project_name project_desc <<< "$project_info"

        if resource_exists "$existing_projects" "$project_name"; then
            print_info "Project already exists: $project_name"
            count_skipped "projects"
        else
            if $os project create "$project_name" --description "$project_desc" >/dev/null 2>&1; then
                print_success "Created project: $project_name"
                count_created "projects"
            else
                print_error "Failed to create project: $project_name"
            fi
        fi
    done
}

# ============================================================================
# Quota Configuration
# ============================================================================

set_quotas() {
    print_section "Configuring Project Quotas"

    # Define quotas: project_name:zones:zone_recordsets:zone_records:recordset_records
    local quota_configs=(
        "project1:10:100:100:20"
        "project2:5:50:50:10"
        "project3:3:30:30:10"
        "admin-project:50:500:500:50"
    )

    for quota_config in "${quota_configs[@]}"; do
        IFS=':' read -r project_name zones zone_recordsets zone_records recordset_records <<< "$quota_config"

        local project_id=$(get_project_id "$project_name")
        if [[ -z "$project_id" ]]; then
            print_warning "Project not found, skipping quota: $project_name"
            continue
        fi

        if $os dns quota set --project-id "$project_id" \
            --zones "$zones" \
            --zone-recordsets "$zone_recordsets" \
            --zone-records "$zone_records" \
            --recordset-records "$recordset_records" >/dev/null 2>&1; then
            print_success "Set quotas for $project_name (zones:$zones, recordsets:$zone_recordsets)"
            count_created "quotas"
        else
            print_error "Failed to set quotas for: $project_name"
        fi
    done
}

# ============================================================================
# Blacklist Creation
# ============================================================================

create_blacklists() {
    print_section "Creating Blacklists"

    local blacklists=(
        ".*spam.*:Block zones containing spam"
        ".*test123.*:Block zones containing test123"
        "^blocked\\..*:Block zones starting with blocked"
        ".*\\.invalid$:Block zones ending with .invalid"
    )

    local existing_blacklists=$($os zone blacklist list -c pattern -f value 2>/dev/null || echo "")

    for blacklist_info in "${blacklists[@]}"; do
        IFS=':' read -r pattern description <<< "$blacklist_info"

        if resource_exists "$existing_blacklists" "$pattern"; then
            print_info "Blacklist already exists: $pattern"
            count_skipped "blacklists"
        else
            if $os zone blacklist create --pattern "$pattern" --description "$description" >/dev/null 2>&1; then
                print_success "Created blacklist: $pattern"
                count_created "blacklists"
            else
                print_error "Failed to create blacklist: $pattern"
            fi
        fi
    done
}

# ============================================================================
# Zone Creation
# ============================================================================

create_zones() {
    print_section "Creating DNS Zones"

    # Define zones: project_name:zone_name:email:ttl:description
    local zones=(
        # Project 1 zones
        "project1:example.com.:admin@example.com:3600:Primary test zone"
        "project1:test.org.:hostmaster@test.org:7200:Testing zone"
        "project1:api.dev.:devops@api.dev:3600:API development zone"
        "project1:webapp.io.:admin@webapp.io:86400:Web application zone"
        "project1:myapp.cloud.:ops@myapp.cloud:3600:Cloud application zone"
        # Project 2 zones
        "project2:service.net.:admin@service.net:7200:Service zone"
        "project2:backend.dev.:backend@backend.dev:3600:Backend development zone"
        "project2:shared.edu.:admin@shared.edu:3600:Shared educational zone"
        # Project 3 zones
        "project3:partner.com.:contact@partner.com:3600:Partner zone"
        "project3:external.org.:external@external.org:7200:External zone"
        # Admin project zones
        "admin-project:admin.local.:root@admin.local:3600:Admin internal zone"
        "admin-project:internal.cloud.:ops@internal.cloud:3600:Internal cloud zone"
    )

    local existing_zones=$($os zone list --all-projects -c name -f value 2>/dev/null || echo "")

    for zone_info in "${zones[@]}"; do
        IFS=':' read -r project_name zone_name email ttl description <<< "$zone_info"

        local project_id=$(get_project_id "$project_name")
        if [[ -z "$project_id" ]]; then
            print_warning "Project not found, skipping zone: $project_name"
            continue
        fi

        if resource_exists "$existing_zones" "$zone_name"; then
            print_info "Zone already exists: $zone_name"
            count_skipped "zones"
        else
            if OS_PROJECT_ID="$project_id" $os zone create \
                --email "$email" \
                --ttl "$ttl" \
                --description "$description" \
                "$zone_name" >/dev/null 2>&1; then
                print_success "Created zone: $zone_name (project: $project_name)"
                count_created "zones"
            else
                print_error "Failed to create zone: $zone_name"
            fi
        fi
    done
}

# ============================================================================
# Zone Sharing
# ============================================================================

share_zones() {
    print_section "Sharing Zones Between Projects"

    # Define shares: zone_name:target_project_name
    local shares=(
        "example.com.:project2"
        "api.dev.:project3"
        "shared.edu.:project1"
        "shared.edu.:project3"
        "internal.cloud.:project1"
    )

    for share_info in "${shares[@]}"; do
        IFS=':' read -r zone_name target_project_name <<< "$share_info"

        local target_project_id=$(get_project_id "$target_project_name")
        if [[ -z "$target_project_id" ]]; then
            print_warning "Target project not found, skipping share: $target_project_name"
            continue
        fi

        # Check if share already exists
        local existing_shares=$($os zone share list "$zone_name" -c target_project_id -f value 2>/dev/null || echo "")

        if resource_exists "$existing_shares" "$target_project_id"; then
            print_info "Zone already shared: $zone_name -> $target_project_name"
            count_skipped "shares"
        else
            if $os zone share create "$zone_name" "$target_project_id" >/dev/null 2>&1; then
                print_success "Shared zone: $zone_name -> $target_project_name"
                count_created "shares"
            else
                print_error "Failed to share zone: $zone_name -> $target_project_name"
            fi
        fi
    done
}

# ============================================================================
# Recordset Creation
# ============================================================================

create_recordsets() {
    print_section "Creating DNS Recordsets"

    print_info "Creating A records..."
    create_a_records

    print_info "Creating AAAA records..."
    create_aaaa_records

    print_info "Creating CNAME records..."
    create_cname_records

    print_info "Creating MX records..."
    create_mx_records

    print_info "Creating TXT records..."
    create_txt_records

    print_info "Creating SRV records..."
    create_srv_records
}

create_a_records() {
    # Format: zone:name:ip1:ip2:ip3 (multiple IPs for round-robin)
    local a_records=(
        "example.com.:www:192.168.1.10:192.168.1.11"
        "example.com.:web:10.0.0.10:10.0.0.11:10.0.0.12"
        "example.com.:db1:192.168.2.20"
        "example.com.:db2:192.168.2.21"
        "example.com.:api:172.16.0.30:172.16.0.31"
        "test.org.:www:203.0.113.10"
        "test.org.:app:203.0.113.20:203.0.113.21"
        "test.org.:cache:10.1.1.50:10.1.1.51"
        "api.dev.:v1:192.168.10.100"
        "api.dev.:v2:192.168.10.101"
        "api.dev.:staging:192.168.10.200"
        "webapp.io.:frontend:198.51.100.10:198.51.100.11"
        "webapp.io.:backend:198.51.100.20"
        "service.net.:api:172.20.0.10"
        "service.net.:web:172.20.0.20:172.20.0.21"
        "partner.com.:www:203.0.114.10"
        "admin.local.:portal:10.255.0.10"
    )

    for record_info in "${a_records[@]}"; do
        IFS=':' read -r zone name ip1 ip2 ip3 <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")
        local record_fqdn="${name}.${zone}"

        if resource_exists "$existing_records" "$record_fqdn"; then
            count_skipped "recordsets"
        else
            local record_args="--type A"
            [[ -n "$ip1" ]] && record_args="$record_args --record $ip1"
            [[ -n "$ip2" ]] && record_args="$record_args --record $ip2"
            [[ -n "$ip3" ]] && record_args="$record_args --record $ip3"

            if $os recordset create $record_args "$zone" "$name" >/dev/null 2>&1; then
                print_success "Created A record: $record_fqdn"
                count_created "recordsets"
            else
                print_error "Failed to create A record: $record_fqdn"
            fi
        fi
    done
}

create_aaaa_records() {
    # IPv6 records
    local aaaa_records=(
        "example.com.:www:2001:db8::1:2001:db8::2"
        "example.com.:web:2001:db8::10"
        "test.org.:www:2001:db8:1::1"
        "api.dev.:v1:2001:db8:2::100"
        "webapp.io.:frontend:2001:db8:3::10:2001:db8:3::11"
        "service.net.:api:2001:db8:4::10"
    )

    for record_info in "${aaaa_records[@]}"; do
        IFS=':' read -r zone name ip1 ip2 <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")
        local record_fqdn="${name}.${zone}"

        if resource_exists "$existing_records" "$record_fqdn"; then
            count_skipped "recordsets"
        else
            local record_args="--type AAAA"
            [[ -n "$ip1" ]] && record_args="$record_args --record $ip1"
            [[ -n "$ip2" ]] && record_args="$record_args --record $ip2"

            if $os recordset create $record_args "$zone" "$name" >/dev/null 2>&1; then
                print_success "Created AAAA record: $record_fqdn"
                count_created "recordsets"
            else
                print_error "Failed to create AAAA record: $record_fqdn"
            fi
        fi
    done
}

create_cname_records() {
    # CNAME records: zone:name:target
    local cname_records=(
        "example.com.:blog:www.example.com."
        "example.com.:shop:web.example.com."
        "example.com.:docs:www.example.com."
        "test.org.:mail:www.test.org."
        "test.org.:ftp:www.test.org."
        "api.dev.:latest:v2.api.dev."
        "webapp.io.:app:frontend.webapp.io."
        "service.net.:portal:web.service.net."
    )

    for record_info in "${cname_records[@]}"; do
        IFS=':' read -r zone name target <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")
        local record_fqdn="${name}.${zone}"

        if resource_exists "$existing_records" "$record_fqdn"; then
            count_skipped "recordsets"
        else
            if $os recordset create --type CNAME --record "$target" "$zone" "$name" >/dev/null 2>&1; then
                print_success "Created CNAME record: $record_fqdn -> $target"
                count_created "recordsets"
            else
                print_error "Failed to create CNAME record: $record_fqdn"
            fi
        fi
    done
}

create_mx_records() {
    # MX records with priorities: zone:priority1:host1:priority2:host2
    local mx_records=(
        "example.com.:10:mail1.example.com.:20:mail2.example.com."
        "test.org.:10:mx1.test.org.:20:mx2.test.org."
        "webapp.io.:5:mail.webapp.io."
        "partner.com.:10:mail.partner.com."
    )

    for record_info in "${mx_records[@]}"; do
        IFS=':' read -r zone pri1 host1 pri2 host2 <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")

        # MX records use @ for the zone apex
        if resource_exists "$existing_records" "$zone"; then
            count_skipped "recordsets"
        else
            local record_args="--type MX"
            [[ -n "$pri1" && -n "$host1" ]] && record_args="$record_args --record \"$pri1 $host1\""
            [[ -n "$pri2" && -n "$host2" ]] && record_args="$record_args --record \"$pri2 $host2\""

            if eval $os recordset create $record_args "$zone" @ >/dev/null 2>&1; then
                print_success "Created MX record for: $zone"
                count_created "recordsets"
            else
                print_error "Failed to create MX record for: $zone"
            fi
        fi
    done
}

create_txt_records() {
    # TXT records: zone:name:value
    local txt_records=(
        "example.com.:@:v=spf1 mx -all"
        "example.com.:_dmarc:v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com"
        "example.com.:verification:google-site-verification=abc123def456"
        "test.org.:@:v=spf1 include:_spf.google.com ~all"
        "webapp.io.:@:v=spf1 mx a -all"
        "partner.com.:_verification:domain-verification=xyz789"
    )

    for record_info in "${txt_records[@]}"; do
        IFS=':' read -r zone name value <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")
        local record_fqdn
        if [[ "$name" == "@" ]]; then
            record_fqdn="$zone"
        else
            record_fqdn="${name}.${zone}"
        fi

        if resource_exists "$existing_records" "$record_fqdn"; then
            count_skipped "recordsets"
        else
            if $os recordset create --type TXT --record "\"$value\"" "$zone" "$name" >/dev/null 2>&1; then
                print_success "Created TXT record: $record_fqdn"
                count_created "recordsets"
            else
                print_error "Failed to create TXT record: $record_fqdn"
            fi
        fi
    done
}

create_srv_records() {
    # SRV records: zone:name:priority:weight:port:target
    local srv_records=(
        "example.com.:_sip._tcp:10:60:5060:sipserver.example.com."
        "example.com.:_xmpp._tcp:5:30:5222:xmpp.example.com."
        "test.org.:_ldap._tcp:10:100:389:ldap.test.org."
        "service.net.:_http._tcp:10:50:80:web.service.net."
    )

    for record_info in "${srv_records[@]}"; do
        IFS=':' read -r zone name priority weight port target <<< "$record_info"

        local existing_records=$($os recordset list "$zone" -c name -f value 2>/dev/null || echo "")
        local record_fqdn="${name}.${zone}"

        if resource_exists "$existing_records" "$record_fqdn"; then
            count_skipped "recordsets"
        else
            local srv_value="$priority $weight $port $target"
            if $os recordset create --type SRV --record "$srv_value" "$zone" "$name" >/dev/null 2>&1; then
                print_success "Created SRV record: $record_fqdn"
                count_created "recordsets"
            else
                print_error "Failed to create SRV record: $record_fqdn"
            fi
        fi
    done
}

# ============================================================================
# PTR Record Creation
# ============================================================================

create_ptr_records() {
    print_section "Creating PTR Records (Reverse DNS)"

    print_warning "PTR record creation requires Neutron floating IPs."
    print_info "Checking for available floating IPs..."

    # Try to get floating IPs
    local floating_ips=$($os floating ip list -c ID -c "Floating IP Address" -f value 2>/dev/null || echo "")

    if [[ -z "$floating_ips" ]]; then
        print_warning "No floating IPs found. Skipping PTR record creation."
        print_info "To create PTR records, first create floating IPs with:"
        print_info "  openstack floating ip create <external-network>"
        print_info "Then set PTR records with:"
        print_info "  openstack ptr record set <region>:<floating-ip-id> <fqdn>"
        return
    fi

    print_info "Found floating IPs. Creating sample PTR records..."

    # Get the first few floating IPs
    local fip_count=0
    local max_ptrs=3

    while IFS= read -r line; do
        [[ $fip_count -ge $max_ptrs ]] && break

        local fip_id=$(echo "$line" | awk '{print $1}')
        local fip_addr=$(echo "$line" | awk '{print $2}')

        # Use RegionOne as default region (adjust if needed)
        local ptr_id="RegionOne:${fip_id}"
        local ptr_name="host${fip_count}.example.com."

        # Check if PTR record already exists
        local existing_ptr=$($os ptr record show "$ptr_id" -c ptrdname -f value 2>/dev/null || echo "")

        if [[ -n "$existing_ptr" ]]; then
            print_info "PTR record already set for: $fip_addr"
            count_skipped "ptr_records"
        else
            if $os ptr record set "$ptr_id" "$ptr_name" >/dev/null 2>&1; then
                print_success "Created PTR record: $fip_addr -> $ptr_name"
                count_created "ptr_records"
            else
                print_error "Failed to create PTR record for: $fip_addr"
            fi
        fi

        ((fip_count++))
    done <<< "$floating_ips"
}

# ============================================================================
# Summary Report
# ============================================================================

print_summary() {
    print_section "Summary Report"

    echo -e "${BOLD}Resources Created:${NC}"
    for resource_type in "${!CREATED_COUNT[@]}"; do
        echo -e "  ${GREEN}${resource_type}:${NC} ${CREATED_COUNT[$resource_type]}"
    done

    echo ""
    echo -e "${BOLD}Resources Skipped (already exist):${NC}"
    for resource_type in "${!SKIPPED_COUNT[@]}"; do
        echo -e "  ${YELLOW}${resource_type}:${NC} ${SKIPPED_COUNT[$resource_type]}"
    done

    echo ""
    print_success "OpenStack Designate test data population completed!"
    echo ""
    print_info "You can now test various Designate features:"
    echo "  - View zones: openstack zone list"
    echo "  - View recordsets: openstack recordset list <zone>"
    echo "  - View zone shares: openstack zone share list <zone>"
    echo "  - View quotas: openstack dns quota list --project-id <project-id>"
    echo "  - View blacklists: openstack zone blacklist list"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo -e "${BOLD}${CYAN}"
    echo "============================================================"
    echo "  OpenStack Designate Test Data Population Script"
    echo "============================================================"
    echo -e "${NC}"

    # Check if OpenStack CLI is available
    if ! command -v $os &> /dev/null; then
        print_error "OpenStack CLI not found. Please install python-openstackclient."
        exit 1
    fi

    # Check if we have valid credentials
    if ! $os token issue >/dev/null 2>&1; then
        print_error "Not authenticated with OpenStack. Please source your credentials file."
        exit 1
    fi

    print_success "OpenStack CLI found and authenticated"

    # Execute all creation functions
    create_tlds
    create_projects
    set_quotas
    create_blacklists
    create_zones
    share_zones
    create_recordsets
    create_ptr_records

    # Print summary
    print_summary
}

# Run main function
main
