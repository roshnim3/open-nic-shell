#!/usr/bin/env python3
"""
bar_read.py — privileged helper that reads one 32-bit word from the U55C's
PCIe BAR2 at a caller-specified offset.

Intended deployment: copy this file to /usr/local/bin/bar_read (root-owned,
mode 0755), then allow it in /etc/sudoers.d via:

    %sp26-ie497-dl-grp03 ALL=(ALL) NOPASSWD: /usr/local/bin/bar_read *

The hardcoded BDF and the 4-byte read size keep the attack surface tight —
the tool cannot read or write arbitrary files; it can only return 32-bit
words from BAR2 of one specific PCI device. Bounds-checked against the
BAR size reported by fstat.
"""

import mmap
import os
import struct
import sys

BDF = "0000:83:00.0"   # U55C on hft03
RESOURCE = f"/sys/bus/pci/devices/{BDF}/resource2"


def usage():
    sys.stderr.write("Usage: bar_read <offset_hex_or_dec>\n")
    sys.stderr.write("  e.g.  sudo bar_read 0x10000\n")
    sys.exit(1)


def main():
    if len(sys.argv) != 2:
        usage()

    try:
        offset = int(sys.argv[1], 0)   # accepts "0x10000" or "65536"
    except ValueError:
        sys.stderr.write(f"ERROR: '{sys.argv[1]}' is not a valid offset\n")
        sys.exit(1)

    if offset < 0:
        sys.stderr.write("ERROR: offset must be non-negative\n")
        sys.exit(1)

    if not os.path.exists(RESOURCE):
        sys.stderr.write(f"ERROR: {RESOURCE} not found. "
                         f"Is the FPGA enumerated?\n")
        sys.exit(2)

    try:
        fd = os.open(RESOURCE, os.O_RDONLY)
    except PermissionError:
        sys.stderr.write(f"ERROR: cannot open {RESOURCE} (need root)\n")
        sys.exit(3)

    try:
        bar_size = os.fstat(fd).st_size
        if offset + 4 > bar_size:
            sys.stderr.write(
                f"ERROR: offset 0x{offset:X} out of BAR range "
                f"(BAR size = {bar_size} = 0x{bar_size:X})\n"
            )
            sys.exit(1)

        mm = mmap.mmap(fd, bar_size, prot=mmap.PROT_READ)
    finally:
        os.close(fd)

    try:
        raw = bytes(mm[offset:offset + 4])
        val = struct.unpack("<I", raw)[0]
        sys.stdout.write(f"0x{val:08X}\n")
    finally:
        mm.close()


if __name__ == "__main__":
    main()
