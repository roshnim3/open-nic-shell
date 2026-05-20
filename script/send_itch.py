#!/usr/bin/env python3
"""
send_itch.py

Software ITCH packet sender for OpenNIC testing.

This sends UDP packets from hft01 to hft03 through the OpenNIC Linux network
interface. Linux/OpenNIC will add Ethernet, IPv4, and UDP headers. This script
constructs the UDP payload:

    MoldUDP64 header
    ITCH message length
    ITCH Add Order message

Expected receiver:
    hft03 OpenNIC interface listening on UDP port 9000
"""

import socket
import struct
import time
import argparse


def make_moldudp64_header(session: bytes, sequence: int, message_count: int) -> bytes:
    """
    MoldUDP64 header:
        session        10 bytes ASCII
        sequence       8 bytes unsigned integer
        message_count  2 bytes unsigned integer
    """
    if len(session) > 10:
        raise ValueError("Session must be at most 10 bytes")

    session = session.ljust(10, b" ")
    return session + struct.pack(">QH", sequence, message_count)


def make_itch_add_order(
    stock_locate: int,
    tracking_number: int,
    timestamp: int,
    order_ref_number: int,
    buy_sell: str,
    shares: int,
    stock: str,
    price: int,
) -> bytes:
    """
    ITCH Add Order message, type 'A'.

    Layout:
        msg_type          1 byte   ASCII 'A'
        stock_locate      2 bytes
        tracking_number   2 bytes
        timestamp         6 bytes
        order_ref_number  8 bytes
        buy_sell          1 byte   ASCII 'B' or 'S'
        shares            4 bytes
        stock             8 bytes ASCII
        price             4 bytes
    Total: 36 bytes
    """

    if buy_sell not in ("B", "S"):
        raise ValueError("buy_sell must be 'B' or 'S'")

    stock_bytes = stock.encode("ascii").ljust(8, b" ")[:8]

    timestamp_bytes = timestamp.to_bytes(6, byteorder="big")

    return (
        b"A"
        + struct.pack(">HH", stock_locate, tracking_number)
        + timestamp_bytes
        + struct.pack(">Q", order_ref_number)
        + buy_sell.encode("ascii")
        + struct.pack(">I", shares)
        + stock_bytes
        + struct.pack(">I", price)
    )


def make_payload(sequence: int, price: int, shares: int, pad_bytes: int = 0) -> bytes:
    session = b"TESTITCH"

    itch_msg = make_itch_add_order(
        stock_locate=0x1234,
        tracking_number=0x0000,
        timestamp=0x000000002300 + sequence,
        order_ref_number=0x0123ABCD000186A0 + sequence,
        buy_sell="B",
        shares=shares,
        stock="AAPL",
        price=price,
    )

    mold_header = make_moldudp64_header(
        session=session,
        sequence=sequence,
        message_count=1,
    )

    msg_len = struct.pack(">H", len(itch_msg))

    return mold_header + msg_len + itch_msg + (b"\x00" * pad_bytes)


def main() -> None:
    parser = argparse.ArgumentParser(description="Send fake MoldUDP64/ITCH UDP packets")
    parser.add_argument("--dst-ip", required=True, help="Destination IP address, e.g. 10.10.1.2")
    parser.add_argument("--dst-port", type=int, default=9000, help="Destination UDP port")
    parser.add_argument("--src-ip", default=None, help="Optional source IP/interface bind address")
    parser.add_argument("--interval", type=float, default=1.0, help="Seconds between packets")
    parser.add_argument("--count", type=int, default=0, help="Number of packets to send, 0 = forever")
    parser.add_argument("--pad-bytes", type=int, default=0, help="Trailing zero padding appended to the UDP payload")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    if args.src_ip:
        sock.bind((args.src_ip, 0))

    sequence = 1
    sent = 0

    print(f"Sending ITCH UDP packets to {args.dst_ip}:{args.dst_port}")

    while args.count == 0 or sent < args.count:
        price = 9_989_680 + sent
        shares = 1000 + sent

        payload = make_payload(sequence=sequence, price=price, shares=shares, pad_bytes=args.pad_bytes)

        sock.sendto(payload, (args.dst_ip, args.dst_port))

        print(
            f"sent seq={sequence} "
            f"payload_len={len(payload)} "
            f"msg_type=A "
            f"shares={shares} "
            f"price={price}"
        )

        sequence += 1
        sent += 1
        time.sleep(args.interval)


if __name__ == "__main__":
    main()