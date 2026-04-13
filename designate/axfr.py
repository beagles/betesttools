#!/usr/bin/env python3
"""Initiate a DNS zone transfer (AXFR) and display the results.

Usage:
    python3 axfr.py <zone> <server> [--port PORT] [--zone-file]

Examples:
    python3 axfr.py example.com. 192.168.1.10
    python3 axfr.py example.com  10.0.0.53 --zone-file
    python3 axfr.py example.com  10.0.0.53 -p 5354
"""

import argparse
import sys

import dns.query
import dns.zone
import dns.rdatatype
import dns.name


def do_axfr(zone_name, server, port=53, timeout=30):
    """Perform an AXFR for *zone_name* against *server*.

    Returns a dns.zone.Zone on success, or raises on failure.
    """
    zone = dns.zone.from_xfr(
        dns.query.xfr(server, zone_name, port=port, timeout=timeout)
    )
    return zone


def print_tabular(zone, zone_name):
    """Print transferred records in a readable tabular format."""
    print(f"\n; Zone transfer for {zone_name}")
    print(f"; {'-' * 60}")
    print(f"{'NAME':<40} {'TTL':>6}  {'TYPE':<8} {'DATA'}")
    print(f"{'-'*40} {'-'*6}  {'-'*8} {'-'*40}")

    origin = zone.origin
    for name in sorted(zone.nodes.keys()):
        fqdn = name.derelativize(origin)
        for rdataset in sorted(zone.nodes[name].rdatasets,
                               key=lambda r: r.rdtype):
            rtype = dns.rdatatype.to_text(rdataset.rdtype)
            for rdata in rdataset:
                print(f"{str(fqdn):<40} {rdataset.ttl:>6}  {rtype:<8} {rdata}")


def print_zone_file(zone):
    """Print transferred records in BIND zone-file format."""
    zone.to_text(sys.stdout)


def main():
    parser = argparse.ArgumentParser(
        description="Initiate a DNS zone transfer (AXFR)."
    )
    parser.add_argument("zone", help="Zone name to transfer (e.g. example.com)")
    parser.add_argument("server", help="IP address of the DNS server")
    parser.add_argument(
        "--zone-file", action="store_true",
        help="Output in BIND zone-file format instead of tabular",
    )
    parser.add_argument(
        "--port", "-p", type=int, default=53,
        help="DNS server port (default: 53)",
    )
    parser.add_argument(
        "--timeout", type=int, default=30,
        help="Query timeout in seconds (default: 30)",
    )
    args = parser.parse_args()

    # Ensure the zone name is fully qualified
    zone_name = args.zone
    if not zone_name.endswith("."):
        zone_name += "."

    try:
        zone = do_axfr(zone_name, args.server, port=args.port,
                       timeout=args.timeout)
    except dns.exception.FormError as exc:
        print(f"Error: zone transfer refused or malformed response: {exc}",
              file=sys.stderr)
        sys.exit(1)
    except dns.xfr.UseTCP:
        # Shouldn't happen as dns.query.xfr already uses TCP, but handle it
        print("Error: server requires TCP (unexpected).", file=sys.stderr)
        sys.exit(1)
    except OSError as exc:
        print(f"Error: could not connect to {args.server}: {exc}",
              file=sys.stderr)
        sys.exit(1)

    if args.zone_file:
        print_zone_file(zone)
    else:
        print_tabular(zone, zone_name)

    record_count = sum(
        len(rdataset)
        for node in zone.nodes.values()
        for rdataset in node.rdatasets
    )
    print(f"\n; Transfer complete: {record_count} records received.")


if __name__ == "__main__":
    main()
