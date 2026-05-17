#!/usr/bin/env python3
"""
read_parser_regs.py — dump the OpenNIC custom-parser AXI-Lite registers.

The p2p_322mhz plugin's register block is mapped into the host's PCIe BAR2.
Per box_322mhz_address_map.v, the plugin lives at box-offset 0x0000, and the
box itself is at BAR2 system-level offset 0x10000. So every register's
absolute BAR2 offset = 0x10000 + register_offset_within_plugin.

Usage:
    sudo python3 read_parser_regs.py --bdf 0000:03:00.0

Requires root because /sys/bus/pci/devices/<bdf>/resource2 is root-owned.
Pure stdlib (mmap + struct), no extra deps.
"""

import argparse
import mmap
import os
import struct
import sys

# BAR2 offset to the p2p plugin's register block. Box base + p2p sub-base.
PLUGIN_BASE = 0x10000

# Register map (offsets within the plugin, mirroring p2p_322mhz.sv localparams)
REGS = [
    (0x00, "REG_MAGIC"),
    (0x04, "REG_VERSION"),
    (0x08, "REG_PACKET_COUNT"),
    (0x0C, "REG_PARSED_MSG_COUNT"),
    (0x10, "REG_LAST_MSG_TYPE"),
    (0x14, "REG_LAST_SRC_IP"),
    (0x18, "REG_LAST_DST_IP"),
    (0x1C, "REG_LAST_PORTS"),
    (0x20, "REG_LAST_SEQ_LOW"),
    (0x24, "REG_LAST_SEQ_HIGH"),
    (0x28, "REG_LAST_MSG_NUM"),
    (0x2C, "REG_LAST_STOCK_LOCATE"),
    (0x30, "REG_LAST_TIMESTAMP_LOW"),
    (0x34, "REG_LAST_TIMESTAMP_HIGH"),
    (0x38, "REG_LAST_REF_NUM_LOW"),
    (0x3C, "REG_LAST_REF_NUM_HIGH"),
    (0x40, "REG_LAST_BUY_SELL"),
    (0x44, "REG_LAST_SHARE_AMT"),
    (0x48, "REG_LAST_STOCK_SYM_LOW"),
    (0x4C, "REG_LAST_STOCK_SYM_HIGH"),
    (0x50, "REG_LAST_PRICE"),
    (0x54, "REG_PARSER_STATUS"),
    (0x58, "REG_CLEAR_COUNTS"),
    (0x5C, "REG_COUNT_ADD_ORDER"),
    (0x60, "REG_COUNT_ORDER_EXECUTED"),
    (0x64, "REG_COUNT_STOCK_ACTION"),
    (0x68, "REG_COUNT_UNKNOWN"),
]


def decode(name, val):
    """Pretty-print sidecar for a few registers."""
    if name == "REG_MAGIC":
        ascii_form = "".join(
            chr((val >> (8 * i)) & 0xFF) for i in range(3, -1, -1)
        )
        return f'"{ascii_form}"'
    if name == "REG_LAST_MSG_TYPE":
        c = val & 0xFF
        if 0x20 <= c <= 0x7E:
            return f"'{chr(c)}'"
        return f"0x{c:02X}"
    if name == "REG_LAST_BUY_SELL":
        c = val & 0xFF
        if c == ord("B"):
            return "'B' (buy)"
        if c == ord("S"):
            return "'S' (sell)"
        return f"0x{c:02X}"
    if name in ("REG_LAST_SRC_IP", "REG_LAST_DST_IP"):
        return ".".join(str((val >> (8 * i)) & 0xFF) for i in range(3, -1, -1))
    if name == "REG_LAST_PORTS":
        return f"src={val >> 16}  dst={val & 0xFFFF}"
    if name in (
        "REG_LAST_STOCK_SYM_LOW",
        "REG_LAST_STOCK_SYM_HIGH",
    ):
        chars = "".join(
            chr((val >> (8 * i)) & 0xFF) if 0x20 <= ((val >> (8 * i)) & 0xFF) <= 0x7E else "."
            for i in range(3, -1, -1)
        )
        return f'"{chars}"'
    if name in (
        "REG_PACKET_COUNT",
        "REG_PARSED_MSG_COUNT",
        "REG_LAST_SHARE_AMT",
        "REG_LAST_PRICE",
        "REG_COUNT_ADD_ORDER",
        "REG_COUNT_ORDER_EXECUTED",
        "REG_COUNT_STOCK_ACTION",
        "REG_COUNT_UNKNOWN",
    ):
        return f"({val})"
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--bdf",
        default="0000:03:00.0",
        help="PCI BDF of the U55C (default: 0000:03:00.0)",
    )
    args = ap.parse_args()

    resource_path = f"/sys/bus/pci/devices/{args.bdf}/resource2"
    if not os.path.exists(resource_path):
        print(f"ERROR: {resource_path} does not exist", file=sys.stderr)
        print("       Check that the BDF is correct and the FPGA is enumerated:", file=sys.stderr)
        print("       lspci | grep -i xilinx", file=sys.stderr)
        sys.exit(1)

    try:
        fd = os.open(resource_path, os.O_RDONLY)
    except PermissionError:
        print(f"ERROR: cannot open {resource_path} (need root). Re-run with sudo.", file=sys.stderr)
        sys.exit(1)

    bar_size = os.fstat(fd).st_size
    mm = mmap.mmap(fd, bar_size, prot=mmap.PROT_READ)
    os.close(fd)

    print(f"BAR2 mapped, size = {bar_size} bytes ({bar_size // 1024} KB)")
    print(f"Plugin register block at BAR2 offset 0x{PLUGIN_BASE:08X}\n")
    print(f"  {'Register':<26} {'Value':<14} Decoded")
    print(f"  {'-' * 26} {'-' * 14} {'-' * 24}")

    for off, name in REGS:
        absolute = PLUGIN_BASE + off
        raw = bytes(mm[absolute:absolute + 4])
        val = struct.unpack("<I", raw)[0]
        print(f"  {name:<26} 0x{val:08X}     {decode(name, val)}")

    mm.close()


if __name__ == "__main__":
    main()
