#!/usr/bin/env python3
"""
read_parser_regs.py — unprivileged wrapper that dumps the OpenNIC p2p
plugin's AXI-Lite register block.

Calls `sudo /usr/local/bin/bar_read <offset>` once per register and decodes
the result. This script itself runs without sudo — only the inner
bar_read calls are privileged. All register knowledge (offsets, names,
decoding) lives here, where students can edit it freely without touching
the privileged tool.

The p2p_322mhz plugin sits at BAR2 offset 0x200000: Box1 @ 322MHz is at
0x200000 in system_config_address_map.sv, and p2p is at offset 0x0 within
the box per box_322mhz_address_map.v.

Usage:
    python3 read_parser_regs.py
"""

import subprocess
import sys

BAR_READ_CMD = ["sudo", "/usr/local/bin/bar_read"]
PLUGIN_BASE = 0x200000

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


def read_one(offset):
    """Run bar_read for one offset, return the value as an int."""
    result = subprocess.run(
        BAR_READ_CMD + [f"0x{offset:X}"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        sys.stderr.write(
            f"bar_read failed for offset 0x{offset:X} "
            f"(exit {result.returncode}):\n{result.stderr}"
        )
        sys.exit(result.returncode)
    return int(result.stdout.strip(), 0)


def decode(name, val):
    """Pretty-print sidecar for a few registers."""
    if name == "REG_MAGIC":
        chars = "".join(
            chr((val >> (8 * i)) & 0xFF) for i in range(3, -1, -1)
        )
        return f'"{chars}"'
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
    if name in ("REG_LAST_STOCK_SYM_LOW", "REG_LAST_STOCK_SYM_HIGH"):
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
    print(f"  {'Register':<26} {'Value':<14} Decoded")
    print(f"  {'-' * 26} {'-' * 14} {'-' * 24}")
    for off, name in REGS:
        val = read_one(PLUGIN_BASE + off)
        print(f"  {name:<26} 0x{val:08X}     {decode(name, val)}")


if __name__ == "__main__":
    main()
