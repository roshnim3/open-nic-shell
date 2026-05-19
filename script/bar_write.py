#!/usr/bin/env python3
"""
bar_write.py — privileged helper that writes one 32-bit word to the U55C's
PCIe BAR2 at a caller-specified offset.

Mirrors bar_read.py: hardcoded BDF, 4-byte access size, bounds-checked
against BAR size from fstat. Intended for diagnostic register pokes such
as enabling CMAC near-end loopback.

Usage:
    sudo python3 bar_write.py <offset_hex_or_dec> <value_hex_or_dec>
    e.g.  sudo python3 bar_write.py 0x8090 0x2222
"""

import mmap
import os
import struct
import sys

BDF = "0000:83:00.0"
RESOURCE = f"/sys/bus/pci/devices/{BDF}/resource2"


def usage():
    sys.stderr.write("Usage: bar_write <offset_hex_or_dec> <value_hex_or_dec>\n")
    sys.stderr.write("  e.g.  sudo bar_write 0x8090 0x2222\n")
    sys.exit(1)


def main():
    if len(sys.argv) != 3:
        usage()

    try:
        offset = int(sys.argv[1], 0)
        value = int(sys.argv[2], 0)
    except ValueError:
        sys.stderr.write(
            f"ERROR: arguments must be integers (got {sys.argv[1]!r}, {sys.argv[2]!r})\n"
        )
        sys.exit(1)

    if offset < 0:
        sys.stderr.write("ERROR: offset must be non-negative\n")
        sys.exit(1)

    if not (0 <= value < (1 << 32)):
        sys.stderr.write("ERROR: value must fit in 32 bits\n")
        sys.exit(1)

    if not os.path.exists(RESOURCE):
        sys.stderr.write(f"ERROR: {RESOURCE} not found. Is the FPGA enumerated?\n")
        sys.exit(2)

    try:
        fd = os.open(RESOURCE, os.O_RDWR)
    except PermissionError:
        sys.stderr.write(f"ERROR: cannot open {RESOURCE} for write (need root)\n")
        sys.exit(3)

    try:
        bar_size = os.fstat(fd).st_size
        if offset + 4 > bar_size:
            sys.stderr.write(
                f"ERROR: offset 0x{offset:X} out of BAR range "
                f"(BAR size = {bar_size} = 0x{bar_size:X})\n"
            )
            sys.exit(1)

        mm = mmap.mmap(fd, bar_size, prot=mmap.PROT_READ | mmap.PROT_WRITE)
    finally:
        os.close(fd)

    try:
        mm[offset:offset + 4] = struct.pack("<I", value)
        sys.stdout.write(f"wrote 0x{value:08X} -> BAR2 0x{offset:X}\n")
    finally:
        mm.close()


if __name__ == "__main__":
    main()
