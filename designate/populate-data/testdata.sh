#!/bin/bash
#
# OpenStack Designate Test Data Definitions
#
# This file contains all test data used by the Designate populate and
# verification scripts. It serves as a single source of truth to ensure
# consistency across simple.sh, simplecheck.sh, and dnscheck.sh.
#
# Usage:
#   source /path/to/testdata.sh
#
# Note: This file is meant to be sourced, not executed directly.
#

# ============================================================================
# TLD Definitions
# ============================================================================

# TLDs to create (without trailing dot)
TLDS=("com" "org" "net" "edu" "io" "dev" "cloud" "local")

# ============================================================================
# Project Definitions
# ============================================================================

# Projects: name:description
PROJECTS=(
    "project1:Primary testing project"
    "project2:Secondary testing project"
    "project3:Tertiary testing project"
    "admin-project:Administrative testing project"
)

# ============================================================================
# User Definitions
# ============================================================================

# Users: username:password:project_name
# Each user is assigned the admin role on their project
USERS=(
    "project1-user:password1:project1"
    "project2-user:password2:project2"
    "project3-user:password3:project3"
    "admin-user:adminpass:admin-project"
)

# ============================================================================
# Quota Definitions
# ============================================================================

# Quotas: project_name:zones:zone_recordsets:zone_records:recordset_records
QUOTAS=(
    "project1:10:100:100:20"
    "project2:5:50:50:10"
    "project3:3:30:30:10"
    "admin-project:50:500:500:50"
)

# ============================================================================
# Blacklist Definitions
# ============================================================================

# Blacklists: pattern:description
BLACKLISTS=(
    ".*spam.*:Block zones containing spam"
    ".*test123.*:Block zones containing test123"
    "^blocked\\..*:Block zones starting with blocked"
    ".*\\.invalid$:Block zones ending with .invalid"
)

# ============================================================================
# Zone Definitions
# ============================================================================

# Zones: project_name:zone_name:email:ttl:description
ZONES=(
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

# ============================================================================
# A Record Definitions
# ============================================================================

# A Records: zone:name:ip1:ip2:ip3 (multiple IPs for round-robin)
A_RECORDS=(
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

# ============================================================================
# AAAA Record Definitions (IPv6)
# ============================================================================

# AAAA Records: zone:name:ip1:ip2 (IPv6 addresses)
AAAA_RECORDS=(
    "example.com.#www#2001:db8::1:2001:db8::2"
    "example.com.#web#:2001:db8::10"
    "test.org.#www#2001:db8:1::1"
    "api.dev.#v1#2001:db8:2::100"
    "webapp.io.#frontend#2001:db8:3::10:2001:db8:3::11"
    "service.net.#ap#2001:db8:4::10"
)

# ============================================================================
# CNAME Record Definitions
# ============================================================================

# CNAME Records: zone:name:target
CNAME_RECORDS=(
    "example.com.:blog:www.example.com."
    "example.com.:shop:web.example.com."
    "example.com.:docs:www.example.com."
    "test.org.:mail:www.test.org."
    "test.org.:ftp:www.test.org."
    "api.dev.:latest:v2.api.dev."
    "webapp.io.:app:frontend.webapp.io."
    "service.net.:portal:web.service.net."
)

# ============================================================================
# MX Record Definitions
# ============================================================================

# MX Records: zone:name:priority1:host1:priority2:host2
MX_RECORDS=(
    "example.com.:mail.example.com.:10:mail1.example.com.:20:mail2.example.com."
    "test.org.:mx.test.org.:10:mx1.test.org.:20:mx2.test.org."
    "webapp.io.:webmail.webapp.io.:5:mail.webapp.io."
    "partner.com.:mail.partner.com.:10:mail1.partner.com."
)

# ============================================================================
# TXT Record Definitions
# ============================================================================

# TXT Records: zone:name:value
TXT_RECORDS=(
    "example.com.:@:v=spf1 mx -all"
    "example.com.:_dmarc:v=DMARC1; p=quarantine; rua=mailto:postmaster@example.com"
    "example.com.:verification:google-site-verification=abc123def456"
    "test.org.:@:v=spf1 include:_spf.google.com ~all"
    "webapp.io.:@:v=spf1 mx a -all"
    "partner.com.:_verification:domain-verification=xyz789"
)

# ============================================================================
# SRV Record Definitions
# ============================================================================

# SRV Records: zone:name:priority:weight:port:target
SRV_RECORDS=(
    "example.com.:_sip._tcp:10:60:5060:sipserver.example.com."
    "example.com.:_xmpp._tcp:5:30:5222:xmpp.example.com."
    "test.org.:_ldap._tcp:10:100:389:ldap.test.org."
    "service.net.:_http._tcp:10:50:80:web.service.net."
)

# ============================================================================
# Helper Functions for Data Access
# ============================================================================

# Get zone owner project from ZONES array by zone name
get_zone_owner_project() {
    local zone_name=$1
    for zone_info in "${ZONES[@]}"; do
        IFS=':' read -r project zone email ttl description <<< "$zone_info"
        if [[ "$zone" == "$zone_name" ]]; then
            echo "$project"
            return 0
        fi
    done
    return 1
}

# Get zone email from ZONES array by zone name
get_zone_email() {
    local zone_name=$1
    for zone_info in "${ZONES[@]}"; do
        IFS=':' read -r project zone email ttl description <<< "$zone_info"
        if [[ "$zone" == "$zone_name" ]]; then
            echo "$email"
            return 0
        fi
    done
    return 1
}

# Get all zones for verification (just zone names)
get_all_zone_names() {
    for zone_info in "${ZONES[@]}"; do
        IFS=':' read -r project zone email ttl description <<< "$zone_info"
        echo "$zone"
    done
}

# Get A record values for a specific FQDN
get_a_record_values() {
    local query_fqdn=$1
    for record_info in "${A_RECORDS[@]}"; do
        IFS=':' read -r zone name ip1 ip2 ip3 <<< "$record_info"
        local fqdn="${name}.${zone}"
        if [[ "$fqdn" == "$query_fqdn" ]]; then
            local values=()
            [[ -n "$ip1" ]] && values+=("$ip1")
            [[ -n "$ip2" ]] && values+=("$ip2")
            [[ -n "$ip3" ]] && values+=("$ip3")
            echo "${values[@]}"
            return 0
        fi
    done
    return 1
}

# Get AAAA record values for a specific FQDN
get_aaaa_record_values() {
    local query_fqdn=$1
    for record_info in "${AAAA_RECORDS[@]}"; do
        IFS=':' read -r zone name ip1 ip2 <<< "$record_info"
        local fqdn="${name}.${zone}"
        if [[ "$fqdn" == "$query_fqdn" ]]; then
            local values=()
            [[ -n "$ip1" ]] && values+=("$ip1")
            [[ -n "$ip2" ]] && values+=("$ip2")
            echo "${values[@]}"
            return 0
        fi
    done
    return 1
}

# Get CNAME target for a specific FQDN
get_cname_target() {
    local query_fqdn=$1
    for record_info in "${CNAME_RECORDS[@]}"; do
        IFS=':' read -r zone name target <<< "$record_info"
        local fqdn="${name}.${zone}"
        if [[ "$fqdn" == "$query_fqdn" ]]; then
            echo "$target"
            return 0
        fi
    done
    return 1
}

# Get MX record values for a zone
get_mx_record_values() {
    local query_zone=$1
    for record_info in "${MX_RECORDS[@]}"; do
        IFS=':' read -r zone pri1 host1 pri2 host2 <<< "$record_info"
        if [[ "$zone" == "$query_zone" ]]; then
            local values=()
            [[ -n "$pri1" && -n "$host1" ]] && values+=("$pri1 $host1")
            [[ -n "$pri2" && -n "$host2" ]] && values+=("$pri2 $host2")
            echo "${values[@]}"
            return 0
        fi
    done
    return 1
}

# Get TXT record value for a specific FQDN or zone
get_txt_record_value() {
    local query_name=$1
    for record_info in "${TXT_RECORDS[@]}"; do
        IFS=':' read -r zone name value <<< "$record_info"
        local fqdn
        if [[ "$name" == "@" ]]; then
            fqdn="$zone"
        else
            fqdn="${name}.${zone}"
        fi
        if [[ "$fqdn" == "$query_name" ]]; then
            echo "$value"
            return 0
        fi
    done
    return 1
}

# Get SRV record value for a specific FQDN
get_srv_record_value() {
    local query_fqdn=$1
    for record_info in "${SRV_RECORDS[@]}"; do
        IFS=':' read -r zone name priority weight port target <<< "$record_info"
        local fqdn="${name}.${zone}"
        if [[ "$fqdn" == "$query_fqdn" ]]; then
            echo "$priority $weight $port $target"
            return 0
        fi
    done
    return 1
}
