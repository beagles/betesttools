# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains testing utilities for OpenStack environments, primarily focused on Designate (DNS as a Service). The tools help populate test data for testing migrations, upgrades, and API calls.

## Repository Structure

```
betesttools/
├── designate/
│   └── populate-data/
│       ├── simple.sh       # Script to populate OpenStack Designate with test data
│       └── simplecheck.sh  # Script to verify test data is present
```

## OpenStack Designate Testing

### Population Script (`designate/populate-data/simple.sh`)

This script comprehensively populates an OpenStack Designate deployment with test data for migration, upgrade, and API testing. It is idempotent and safe to run multiple times.

#### Features

The script creates the following resources:

1. **TLDs (8)**: Top-level domains (com, org, net, edu, io, dev, cloud, local)
2. **Projects (4)**:
   - `project1`: Primary testing project with standard quotas
   - `project2`: Secondary project with restricted quotas
   - `project3`: Zone sharing recipient project
   - `admin-project`: Administrative project with elevated quotas
3. **Quotas (4 sets)**: Different quota configurations per project for testing limits
4. **Blacklists (4)**: Regex patterns to block zone creation (spam, test123, blocked.*, *.invalid)
5. **Zones (12)**: DNS zones distributed across projects with varying TTLs
6. **Zone Shares (5)**: Shared zones between projects for multi-tenant testing
7. **Recordsets (50+)**: Multiple DNS records per zone including:
   - A records (17): IPv4 addresses, including multi-value round-robin records
   - AAAA records (6): IPv6 addresses
   - CNAME records (8): Aliases and canonical names
   - MX records (4): Mail exchange records with priorities
   - TXT records (6): SPF, DMARC, and verification records
   - SRV records (4): Service discovery records
8. **PTR Records**: Reverse DNS for Neutron floating IPs (when available)

#### Usage

**Requirements**:
- OpenStack CLI (`python-openstackclient`) installed
- Authenticated with admin credentials (`source` your OpenStack RC file)
- Designate service available and configured

**Run the script**:
```bash
./designate/populate-data/simple.sh
```

The script will:
- Validate OpenStack CLI availability and authentication
- Create all resources with colored output showing progress
- Skip resources that already exist (idempotent)
- Display a summary report of created and skipped resources
- Provide helpful commands for viewing the created resources

#### Script Design

- **Idempotent**: Safe to run multiple times; checks for existing resources before creating
- **Color-coded output**: Green (success), blue (info), yellow (warning), red (error)
- **Error handling**: Continues on non-critical failures and reports issues
- **Organized structure**: Separate functions for each resource type
- **Summary reporting**: Tracks and displays counts of created and skipped resources

#### Example Verification Commands

After running the script, verify the created resources:

```bash
# View all zones
openstack zone list --all-projects

# View recordsets in a zone
openstack recordset list example.com.

# View zone shares
openstack zone share list example.com.

# View project quotas
openstack dns quota list --project-id $(openstack project show project1 -c id -f value)

# View blacklists
openstack zone blacklist list

# View TLDs
openstack tld list
```

### Verification Script (`designate/populate-data/simplecheck.sh`)

This companion script verifies that all resources created by `simple.sh` are present in the OpenStack Designate deployment. It performs read-only checks and provides a detailed report.

#### Features

The script verifies the presence of:

1. **TLDs (8)**: All expected top-level domains
2. **Projects (4)**: All test projects
3. **Quotas (4 sets)**: Validates quota configurations match expected values
4. **Blacklists (4)**: All regex patterns
5. **Zones (12)**: All DNS zones across projects
6. **Zone Shares (5)**: All shared zone configurations
7. **Recordsets (Sample)**: Representative sample of each record type:
   - A records (5 samples)
   - AAAA records (3 samples)
   - CNAME records (3 samples)
   - MX records (3 zones)
   - TXT records (3 samples)
   - SRV records (3 samples)
8. **PTR Records**: Lists any existing PTR records

#### Usage

**Requirements**:
- OpenStack CLI (`python-openstackclient`) installed
- Authenticated with OpenStack credentials (admin not required for read-only checks)
- Designate service available

**Run the script**:
```bash
./designate/populate-data/simplecheck.sh
```

The script will:
- Validate OpenStack CLI availability and authentication
- Check for each expected resource with color-coded output
- Display a summary showing found vs. missing resources
- Provide guidance if resources are missing

#### Output

- **Green checkmarks (✓)**: Resource found
- **Red crosses (✗)**: Resource missing
- **Blue info (ℹ)**: Informational messages
- **Yellow warnings (⚠)**: Non-critical issues

#### Example Output

```
===================================================
Checking TLDs
===================================================

✓ TLD exists: com
✓ TLD exists: org
✗ TLD missing: dev

===================================================
Verification Summary
===================================================

Resources Found:
  tlds: 7
  projects: 4
  zones: 12
  recordsets: 15

Resources Missing:
  tlds: 1

Overall Status:
  Total Found: 38
  Total Missing: 1

⚠ Some resources are missing. You may need to run simple.sh to create them.
```

#### Use Cases

- **Post-deployment verification**: Confirm all test data was created successfully
- **Migration validation**: Verify data integrity after migrations or upgrades
- **Continuous testing**: Quick health check of test environment
- **Debugging**: Identify which specific resources are missing

## Development Context

This is a utility repository for OpenStack Designate testing. When modifying scripts:

- **Maintain idempotency**: Always check if resources exist before creating them
- **Follow OpenStack CLI patterns**: Use `-c` for column selection and `-f value` for parseable output
- **Zone naming convention**: Zone names must include trailing dot (e.g., `example.com.`), but TLD names should not
- **Project context**: Use `OS_PROJECT_ID` environment variable to create resources in specific projects
- **Error handling**: Use `2>/dev/null || echo ""` pattern for graceful handling of missing resources
- **Admin privileges**: Quotas and blacklists require admin access
- **PTR records**: Require Neutron floating IPs; script handles missing IPs gracefully
