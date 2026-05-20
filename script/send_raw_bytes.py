#!/usr/bin/env python3
"""
send_raw_bytes.py

Diagnostic UDP sender that emits a payload of arbitrary repeated bytes.
Used to probe the parser when we want to control exactly what byte is at
every position of the UDP payload (e.g., to force-trigger an ITCH msg_type
match regardless of byte-offset assumptions).

Example:
    sudo python3 send_raw_bytes.py --src-ip 10.0.0.3 --dst-ip 10.0.0.99 \\
        --count 5 --interval 0.2 --byte 0x41 --length 1000
"""

import argparse
import socket
import time


def main() -> None:
    parser = argparse.ArgumentParser(description="Send a UDP packet of repeated bytes")
    parser.add_argument("--dst-ip", required=True)
    parser.add_argument("--dst-port", type=int, default=9000)
    parser.add_argument("--src-ip", default=None)
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--interval", type=float, default=0.2)
    parser.add_argument("--byte", default="0x41",
                        help="repeated byte value in hex (default 0x41 = 'A')")
    parser.add_argument("--length", type=int, default=1000,
                        help="UDP payload length in bytes")
    args = parser.parse_args()

    byte_val = int(args.byte, 0) & 0xFF
    payload = bytes([byte_val]) * args.length

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.src_ip:
        sock.bind((args.src_ip, 0))

    print(f"sending {args.count} UDP packets to {args.dst_ip}:{args.dst_port}")
    print(f"payload: {args.length} bytes, all 0x{byte_val:02X}")
    if args.src_ip:
        print(f"bound to src {args.src_ip}")

    for i in range(args.count):
        sock.sendto(payload, (args.dst_ip, args.dst_port))
        print(f"  sent {i+1}/{args.count} ({len(payload)} bytes)")
        if i + 1 < args.count:
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
