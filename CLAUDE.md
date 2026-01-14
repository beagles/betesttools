# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains testing utilities for OpenStack environments, primarily focused on Designate (DNS as a Service). The tools help populate test data for testing migrations, upgrades, and API calls.

## Repository Structure

```
betesttools/
├── designate/
│   └── populate-data/
│       ├── testdata.sh     # Common test data definitions (sourced by all scripts)
│       ├── simple.sh       # Script to populate OpenStack Designate with test data
│       ├── simplecheck.sh  # Script to verify test data is present in Designate API
│       └── dnscheck.sh     # Script to verify DNS records are served by DNS servers
```

## OpenStack Designate Testing

### Test Data Architecture (`designate/populate-data/testdata.sh`)

All three scripts source a common data file (`testdata.sh`) that serves as the **single source of truth** for test data. This ensures consistency across creation, verification, and DNS testing.

#### Benefits

- **Single source of truth**: All test data defined in one place
- **Guaranteed consistency**: All scripts use identical test data
- **Easy maintenance**: Update test data in one file, all scripts automatically sync
- **No duplication**: Test data is not repeated across scripts
- **Easy extensibility**: Add new test scenarios by modifying one file

#### Data Definitions

The `testdata.sh` file contains bash arrays defining:

- **TLDs**: 8 top-level domains (com, org, net, edu, io, dev, cloud, local)
- **Projects**: 4 OpenStack projects with descriptions
- **Users**: 4 users (one per project) with passwords and project assignments
- **Quotas**: Quota configurations for each project
- **Blacklists**: 4 regex patterns for blocking zone names
- **Zones**: 12 DNS zones with project, email, TTL, and description
- **Zone Shares**: 5 zone sharing configurations
- **A Records**: 17 IPv4 address records (some with multiple IPs for round-robin)
- **AAAA Records**: 6 IPv6 address records
- **CNAME Records**: 8 canonical name records
- **MX Records**: 4 mail exchange records with priorities
- **TXT Records**: 6 text records (SPF, DMARC, verification)
- **SRV Records**: 4 service discovery records

#### Helper Functions

The file also provides helper functions for data access:
- `get_zone_email()`: Get email address for a zone
- `get_all_zone_names()`: List all zone names
- `get_a_record_values()`: Get IP addresses for an A record
- `get_aaaa_record_values()`: Get IPv6 addresses for an AAAA record
- `get_cname_target()`: Get target for a CNAME record
- `get_mx_record_values()`: Get MX record values with priorities
- `get_txt_record_value()`: Get TXT record value
- `get_srv_record_value()`: Get SRV record value

#### Usage by Scripts

Each script sources the data file at startup:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/testdata.sh"
```

After sourcing, all test data arrays are available:
- `simple.sh` uses the arrays to create resources
- `simplecheck.sh` uses the arrays to verify resource existence
- `dnscheck.sh` uses the arrays to validate DNS record values

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
3. **Users (4)**: One user per project with admin role assigned:
   - `project1-user`: User for project1 with admin role
   - `project2-user`: User for project2 with admin role
   - `project3-user`: User for project3 with admin role
   - `admin-user`: User for admin-project with admin role
4. **Quotas (4 sets)**: Different quota configurations per project for testing limits
5. **Blacklists (4)**: Regex patterns to block zone creation (spam, test123, blocked.*, *.invalid)
6. **Zones (12)**: DNS zones distributed across projects with varying TTLs
7. **Zone Shares (5)**: Shared zones between projects for multi-tenant testing
8. **Recordsets (50+)**: Multiple DNS records per zone including:
   - A records (17): IPv4 addresses, including multi-value round-robin records
   - AAAA records (6): IPv6 addresses
   - CNAME records (8): Aliases and canonical names
   - MX records (4): Mail exchange records with priorities
   - TXT records (6): SPF, DMARC, and verification records
   - SRV records (4): Service discovery records
9. **PTR Records**: Reverse DNS for Neutron floating IPs (when available)

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
3. **Users (4)**: All project users
4. **Role Assignments (4)**: Validates admin role is assigned to each user on their project
5. **Quotas (4 sets)**: Validates quota configurations match expected values
6. **Blacklists (4)**: All regex patterns
7. **Zones (12)**: All DNS zones across projects
8. **Zone Shares (5)**: All shared zone configurations
9. **Recordsets (Sample)**: Representative sample of each record type:
   - A records (5 samples)
   - AAAA records (3 samples)
   - CNAME records (3 samples)
   - MX records (3 zones)
   - TXT records (3 samples)
   - SRV records (3 samples)
10. **PTR Records**: Lists any existing PTR records

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

### DNS Server Verification Script (`designate/populate-data/dnscheck.sh`)

This script uses the `dig` command to verify that DNS records created by `simple.sh` are actually being served by the Designate backend DNS servers **with the correct values**. This validates end-to-end DNS resolution and data integrity.

#### Features

The script validates DNS records by checking both **existence** and **correctness of values**:

1. **SOA Records (6 zones)**: Verifies SOA records contain expected email addresses
2. **NS Records (4 zones)**: Confirms nameserver records exist
3. **A Records (15 checks)**: Validates IPv4 addresses match expected values, including multi-value round-robin records
4. **AAAA Records (6 checks)**: Validates IPv6 addresses match expected values
5. **CNAME Records (8 checks)**: Confirms aliases point to correct targets
6. **MX Records (4 zones)**: Validates mail servers with correct priorities
7. **TXT Records (5 checks)**: Verifies SPF, DMARC, and verification strings
8. **SRV Records (4 checks)**: Validates service records with correct priority, weight, port, and target

**Total**: 52+ DNS queries per server with value validation

**Value Validation**:
- For multi-value records (round-robin), verifies all expected values are present (order doesn't matter)
- For single-value records, ensures exact match
- Shows detailed error messages when values don't match (expected vs. actual)

#### Usage

**Requirements**:
- `dig` command installed:
  - RHEL/CentOS/Rocky: `sudo yum install bind-utils`
  - Debian/Ubuntu: `sudo apt install dnsutils`
  - Alpine: `apk add bind-tools`

**Run the script**:
```bash
# Single DNS server
./designate/populate-data/dnscheck.sh 192.168.1.10

# Multiple DNS servers
./designate/populate-data/dnscheck.sh 192.168.1.10 192.168.1.11

# Multiple servers with IPs from command
./designate/populate-data/dnscheck.sh 10.0.0.53 10.0.0.54 10.0.0.55
```

The script will:
- Test connectivity to each DNS server
- Query each server for all record types created by `simple.sh`
- Display results with color-coded output
- Provide per-server and per-record-type statistics
- Calculate overall success rate

#### Output

- **Green checkmarks (✓)**: DNS query successful, record returned
- **Red crosses (✗)**: DNS query failed or no response
- **Blue info (ℹ)**: Informational messages
- **Yellow warnings (⚠)**: Partial success

#### Example Output

```
===================================================
Checking DNS Server: 192.168.1.10
===================================================

ℹ Testing DNS server connectivity...
✓ DNS server 192.168.1.10 is responding

ℹ Checking A records...
✓ A record (multi-value): www.example.com (A) -> 192.168.1.10 192.168.1.11
✓ A record (multi-value): web.example.com (A) -> 10.0.0.10 10.0.0.11 10.0.0.12
✓ A record: db1.example.com (A) -> 192.168.2.20
✗ A record: db2.example.com (A)
  Expected: 192.168.2.21
  Got: 192.168.2.99

===================================================
DNS Verification Summary
===================================================

Results by DNS Server:
  192.168.1.10:
    Successful queries: 38
    Failed queries: 7
    Success rate: 84%

Results by Record Type (all servers):
  A records: 8 success / 2 failed
  AAAA records: 4 success / 1 failed
  CNAME records: 7 success / 0 failed
  MX records: 4 success / 0 failed
  TXT records: 5 success / 0 failed
  SRV records: 4 success / 0 failed
  SOA records: 6 success / 0 failed

Overall Status:
  Total queries: 52
  Successful: 48
  Failed: 4
  Overall success rate: 92%

✓ All DNS queries returned correct values!
```

#### Use Cases

- **DNS server validation**: Confirm backend DNS servers are serving zones with correct values
- **Data integrity verification**: Ensure DNS records match what was created in Designate
- **Network troubleshooting**: Verify DNS resolution from different network locations
- **Load balancer testing**: Check multiple backend servers are all serving identical data
- **Post-deployment verification**: End-to-end validation after Designate deployment
- **Migration validation**: Confirm DNS records were migrated correctly with accurate values
- **Continuous monitoring**: Regular health checks of DNS infrastructure and data accuracy

#### Comparison with simplecheck.sh

| Aspect | simplecheck.sh | dnscheck.sh |
|--------|----------------|-------------|
| **What it checks** | Designate API database | Actual DNS resolution |
| **Value validation** | Existence only | Existence + correctness |
| **Requirements** | OpenStack CLI | dig command |
| **Auth needed** | Yes (OpenStack) | No |
| **Scope** | All resources | DNS records only |
| **Network** | Checks API endpoint | Checks DNS servers |
| **Use case** | Verify data in database | Verify DNS serving correct data |

**Recommended workflow**:
1. Run `simple.sh` to create test data
2. Run `simplecheck.sh` to verify data in Designate API
3. Run `dnscheck.sh` to verify DNS servers are serving the data

## Development Context

This is a utility repository for OpenStack Designate testing. When modifying scripts:

### Test Data Management

- **Single source of truth**: All test data is defined in `testdata.sh`
- **Modifying test data**: Edit `testdata.sh` only; all three scripts automatically use the updated data
- **Adding new scenarios**: Add new records to the appropriate arrays in `testdata.sh`
- **Consistency**: Never hardcode test data in individual scripts; always use the shared arrays

### OpenStack Patterns

- **Maintain idempotency**: Always check if resources exist before creating them
- **Follow OpenStack CLI patterns**: Use `-c` for column selection and `-f value` for parseable output
- **Zone naming convention**: Zone names must include trailing dot (e.g., `example.com.`), but TLD names should not
- **Project context**: Use `OS_PROJECT_ID` environment variable to create resources in specific projects
- **Error handling**: Use `2>/dev/null || echo ""` pattern for graceful handling of missing resources
- **Admin privileges**: Quotas and blacklists require admin access
- **PTR records**: Require Neutron floating IPs; script handles missing IPs gracefully
