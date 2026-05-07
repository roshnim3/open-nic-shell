#!/usr/bin/env python3
"""
recv_itch.py

Software MoldUDP64 / ITCH packet parser for hft03.

Use this before touching FPGA hardware parsing.

Expected packet format:
    UDP payload =
        10 bytes  MoldUDP64 session
        8 bytes   MoldUDP64 sequence number
        2 bytes   MoldUDP64 message count
        repeated:
            2 bytes ITCH message length
            N bytes ITCH message

Currently supports:
    ITCH Add Order message, type 'A' / 0x41

Run on hft03:
    python3 recv_itch.py --bind-ip 10.10.1.2 --port 9000

Or listen on all interfaces:
    python3 recv_itch.py --port 9000
"""

import argparse
import socket
import struct
from dataclasses import dataclass


@dataclass
class MoldUDP64Header:
    session: str
    sequence: int
    message_count: int


@dataclass
class ITCHAddOrder:
    msg_type: str
    stock_locate: int
    tracking_number: int
    timestamp: int
    order_ref_number: int
    buy_sell: str
    shares: int
    stock: str
    price: int


def parse_moldudp64_header(payload: bytes) -> MoldUDP64Header:
    if len(payload) < 20:
        raise ValueError(f"Payload too short for MoldUDP64 header: {len(payload)} bytes")

    session_bytes = payload[0:10]
    sequence = struct.unpack(">Q", payload[10:18])[0]
    message_count = struct.unpack(">H", payload[18:20])[0]

    session = session_bytes.decode("ascii", errors="replace").rstrip()

    return MoldUDP64Header(
        session=session,
        sequence=sequence,
        message_count=message_count,
    )


def parse_itch_add_order(msg: bytes) -> ITCHAddOrder:
    if len(msg) != 36:
        raise ValueError(f"ITCH Add Order should be 36 bytes, got {len(msg)} bytes")

    msg_type = chr(msg[0])
    stock_locate = struct.unpack(">H", msg[1:3])[0]
    tracking_number = struct.unpack(">H", msg[3:5])[0]
    timestamp = int.from_bytes(msg[5:11], byteorder="big")
    order_ref_number = struct.unpack(">Q", msg[11:19])[0]
    buy_sell = chr(msg[19])
    shares = struct.unpack(">I", msg[20:24])[0]
    stock = msg[24:32].decode("ascii", errors="replace").rstrip()
    price = struct.unpack(">I", msg[32:36])[0]

    return ITCHAddOrder(
        msg_type=msg_type,
        stock_locate=stock_locate,
        tracking_number=tracking_number,
        timestamp=timestamp,
        order_ref_number=order_ref_number,
        buy_sell=buy_sell,
        shares=shares,
        stock=stock,
        price=price,
    )


def parse_itch_message(msg: bytes) -> object:
    if len(msg) == 0:
        raise ValueError("Empty ITCH message")

    msg_type = msg[0]

    if msg_type == 0x41:
        return parse_itch_add_order(msg)

    return {
        "msg_type_hex": f"0x{msg_type:02X}",
        "msg_type_ascii": chr(msg_type) if 32 <= msg_type <= 126 else ".",
        "raw_len": len(msg),
        "raw_hex": msg.hex(),
    }


def parse_payload(payload: bytes) -> tuple[MoldUDP64Header, list[object]]:
    mold = parse_moldudp64_header(payload)

    offset = 20
    messages = []

    for idx in range(mold.message_count):
        if offset + 2 > len(payload):
            raise ValueError(
                f"Missing ITCH length for message {idx}. "
                f"offset={offset}, payload_len={len(payload)}"
            )

        msg_len = struct.unpack(">H", payload[offset:offset + 2])[0]
        offset += 2

        if offset + msg_len > len(payload):
            raise ValueError(
                f"Message {idx} length exceeds payload. "
                f"msg_len={msg_len}, offset={offset}, payload_len={len(payload)}"
            )

        msg = payload[offset:offset + msg_len]
        offset += msg_len

        parsed_msg = parse_itch_message(msg)
        messages.append(parsed_msg)

    if offset != len(payload):
        extra = payload[offset:]
        print(f"WARNING: {len(extra)} trailing bytes after parsed messages: {extra.hex()}")

    return mold, messages


def print_packet(src_addr: tuple[str, int], payload: bytes) -> None:
    print("=" * 80)
    print(f"Received UDP packet from {src_addr[0]}:{src_addr[1]}")
    print(f"UDP payload length: {len(payload)} bytes")
    print(f"Raw payload hex: {payload.hex()}")

    try:
        mold, messages = parse_payload(payload)
    except ValueError as exc:
        print(f"PARSE ERROR: {exc}")
        return

    print()
    print("MoldUDP64 Header")
    print(f"  session       : {mold.session}")
    print(f"  sequence      : {mold.sequence}")
    print(f"  message_count : {mold.message_count}")

    for idx, msg in enumerate(messages):
        print()
        print(f"ITCH Message {idx}")

        if isinstance(msg, ITCHAddOrder):
            print("  type              : Add Order 'A' / 0x41")
            print(f"  stock_locate      : 0x{msg.stock_locate:04X} ({msg.stock_locate})")
            print(f"  tracking_number   : 0x{msg.tracking_number:04X} ({msg.tracking_number})")
            print(f"  timestamp         : 0x{msg.timestamp:012X} ({msg.timestamp})")
            print(f"  order_ref_number  : 0x{msg.order_ref_number:016X} ({msg.order_ref_number})")
            print(f"  buy_sell          : {msg.buy_sell} / 0x{ord(msg.buy_sell):02X}")
            print(f"  shares            : {msg.shares}")
            print(f"  stock             : {msg.stock}")
            print(f"  price             : {msg.price}")
            print(f"  price_decimal     : ${msg.price / 10000:.4f}")
        else:
            print("  unsupported message")
            for key, value in msg.items():
                print(f"  {key:16}: {value}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Receive and parse MoldUDP64/ITCH UDP packets")
    parser.add_argument("--bind-ip", default="0.0.0.0", help="IP to bind to. Default: all interfaces")
    parser.add_argument("--port", type=int, default=9000, help="UDP port to listen on")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((args.bind_ip, args.port))

    print(f"Listening for UDP MoldUDP64/ITCH packets on {args.bind_ip}:{args.port}")

    while True:
        payload, src_addr = sock.recvfrom(65535)
        print_packet(src_addr, payload)


if __name__ == "__main__":
    main()