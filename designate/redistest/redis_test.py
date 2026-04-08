#!/usr/bin/env python3
"""Redis connectivity test tool.

Supports direct Redis connections and Sentinel-based discovery,
with optional TLS for both modes.
"""

import argparse
import logging
import sys
import time

import redis
from redis.sentinel import Sentinel

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger('redis')
logger.setLevel(logging.DEBUG)

def build_ssl_kwargs(args):
    """Build SSL keyword arguments from CLI options."""
    if not args.tls:
        return {}
    kwargs = {"ssl": True}
    if args.ca_cert:
        kwargs["ssl_ca_certs"] = args.ca_cert
    if args.client_cert:
        kwargs["ssl_certfile"] = args.client_cert
    if args.client_key:
        kwargs["ssl_keyfile"] = args.client_key
    if args.skip_verify:
        kwargs["ssl_cert_reqs"] = None
    return kwargs


def connect_direct(args):
    """Connect directly to a Redis server."""
    ssl_kwargs = build_ssl_kwargs(args)
    client = redis.Redis(
        host=args.host,
        port=args.port,
        password=args.password,
        db=args.db,
        decode_responses=True,
        socket_connect_timeout=args.timeout,
        **ssl_kwargs,
    )
    return client


def connect_sentinel(args):
    """Connect via Redis Sentinel."""
    ssl_kwargs = build_ssl_kwargs(args)

    sentinels = []
    for s in args.sentinels:
        if ":" in s:
            host, port = s.rsplit(":", 1)
            sentinels.append((host, int(port)))
        else:
            sentinels.append((s, args.sentinel_port))

    sentinel_ssl_kwargs = {}
    if args.tls_sentinel:
        sentinel_ssl_kwargs["ssl"] = True
        if args.ca_cert:
            sentinel_ssl_kwargs["ssl_ca_certs"] = args.ca_cert
        if args.client_cert:
            sentinel_ssl_kwargs["ssl_certfile"] = args.client_cert
        if args.client_key:
            sentinel_ssl_kwargs["ssl_keyfile"] = args.client_key
        if args.skip_verify:
            sentinel_ssl_kwargs["ssl_cert_reqs"] = None

    sentinel = Sentinel(
        sentinels,
        socket_timeout=args.timeout,
        password=args.sentinel_password,
        **sentinel_ssl_kwargs,
    )

    service = args.sentinel_service
    print(f"Discovering master for service '{service}' via Sentinel...")
    master_addr = sentinel.discover_master(service)
    print(f"  Master: {master_addr[0]}:{master_addr[1]}")

    try:
        slaves = sentinel.discover_slaves(service)
        if slaves:
            for addr in slaves:
                print(f"  Replica: {addr[0]}:{addr[1]}")
        else:
            print("  No replicas found")
    except Exception as e:
        print(f"  Replica discovery failed: {e}")

    client = sentinel.master_for(
        service,
        password=args.password,
        db=args.db,
        decode_responses=True,
        **ssl_kwargs,
    )
    return client


def run_tests(client):
    """Run basic Redis operations and report results."""
    test_key = "_redis_connectivity_test"
    passed = 0
    failed = 0

    def report(name, fn):
        nonlocal passed, failed
        try:
            result = fn()
            print(f"  PASS  {name}: {result}")
            passed += 1
        except Exception as e:
            print(f"  FAIL  {name}: {e}")
            failed += 1

    print("\n--- Connectivity ---")
    report("PING", lambda: client.ping())

    print("\n--- Server Info ---")

    def show_info():
        info = client.info("server")
        version = info.get("redis_version", "unknown")
        mode = info.get("redis_mode", "unknown")
        return f"version={version} mode={mode}"

    report("INFO", show_info)

    print("\n--- Basic Operations ---")
    report("SET", lambda: client.set(test_key, "hello"))
    report("GET", lambda: client.get(test_key))
    report("APPEND", lambda: client.append(test_key, "_world"))
    report("GET (after append)", lambda: client.get(test_key))
    report("DEL", lambda: client.delete(test_key))

    print("\n--- Data Structures ---")
    list_key = test_key + ":list"
    report("LPUSH", lambda: client.lpush(list_key, "a", "b", "c"))
    report("LRANGE", lambda: client.lrange(list_key, 0, -1))
    report("DEL list", lambda: client.delete(list_key))

    hash_key = test_key + ":hash"
    report("HSET", lambda: client.hset(hash_key, mapping={"field1": "val1", "field2": "val2"}))
    report("HGETALL", lambda: client.hgetall(hash_key))
    report("DEL hash", lambda: client.delete(hash_key))

    set_key = test_key + ":set"
    report("SADD", lambda: client.sadd(set_key, "x", "y", "z"))
    report("SMEMBERS", lambda: client.smembers(set_key))
    report("DEL set", lambda: client.delete(set_key))

    print("\n--- Expiry ---")
    report("SET with EX", lambda: client.set(test_key, "expires", ex=60))
    report("TTL", lambda: client.ttl(test_key))
    report("DEL", lambda: client.delete(test_key))

    print(f"\n--- Results: {passed} passed, {failed} failed ---")
    return failed == 0


def main():
    parser = argparse.ArgumentParser(
        description="Test Redis connectivity and basic operations",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  # Direct connection
  %(prog)s -H redis.example.com -p 6379

  # Direct with TLS
  %(prog)s -H redis.example.com -p 6380 --tls --ca-cert /path/to/ca.pem

  # Via Sentinel
  %(prog)s --sentinel -S sentinel1:26379 -S sentinel2:26379 --sentinel-service mymaster

  # Sentinel with TLS on both Sentinel and Redis
  %(prog)s --sentinel -S sentinel1:26379 --sentinel-service mymaster \\
      --tls --tls-sentinel --ca-cert /path/to/ca.pem
""",
    )

    mode = parser.add_argument_group("connection mode")
    mode.add_argument(
        "--sentinel", action="store_true",
        help="Use Sentinel for master discovery",
    )

    direct = parser.add_argument_group("direct connection")
    direct.add_argument("-H", "--host", default="localhost", help="Redis host (default: localhost)")
    direct.add_argument("-p", "--port", type=int, default=6379, help="Redis port (default: 6379)")

    sent = parser.add_argument_group("sentinel connection")
    sent.add_argument(
        "-S", "--sentinels", action="append", default=[],
        help="Sentinel address as host:port (can be repeated)",
    )
    sent.add_argument("--sentinel-port", type=int, default=26379, help="Default Sentinel port (default: 26379)")
    sent.add_argument("--sentinel-service", default="mymaster", help="Sentinel service name (default: mymaster)")
    sent.add_argument("--sentinel-password", default=None, help="Password for Sentinel connections")

    auth = parser.add_argument_group("authentication")
    auth.add_argument("-a", "--password", default=None, help="Redis password")
    auth.add_argument("-n", "--db", type=int, default=0, help="Database number (default: 0)")

    tls = parser.add_argument_group("TLS")
    tls.add_argument("--tls", action="store_true", help="Enable TLS for Redis connections")
    tls.add_argument("--tls-sentinel", action="store_true", help="Enable TLS for Sentinel connections")
    tls.add_argument("--ca-cert", default=None, help="CA certificate file")
    tls.add_argument("--client-cert", default=None, help="Client certificate file")
    tls.add_argument("--client-key", default=None, help="Client private key file")
    tls.add_argument("--skip-verify", action="store_true", help="Skip TLS certificate verification")

    parser.add_argument("--timeout", type=float, default=5.0, help="Connection timeout in seconds (default: 5)")

    args = parser.parse_args()

    if args.sentinel and not args.sentinels:
        parser.error("--sentinel requires at least one -S/--sentinels address")

    try:
        if args.sentinel:
            print(f"Connecting via Sentinel...")
            client = connect_sentinel(args)
        else:
            target = f"{args.host}:{args.port}"
            tls_label = " (TLS)" if args.tls else ""
            print(f"Connecting to {target}{tls_label}...")
            client = connect_direct(args)

        success = run_tests(client)
        client.close()
        sys.exit(0 if success else 1)

    except redis.ConnectionError as e:
        print(f"Connection failed: {e}", file=sys.stderr)
        sys.exit(2)
    except redis.AuthenticationError as e:
        print(f"Authentication failed: {e}", file=sys.stderr)
        sys.exit(3)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()
