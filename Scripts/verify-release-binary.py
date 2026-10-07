#!/usr/bin/env python3
"""Compare initialized Mach-O sections, excluding signing metadata and zero-fill."""
import hashlib
import struct
import sys
from pathlib import Path


def section_hashes(path):
    data = Path(path).read_bytes()
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("expected a little-endian 64-bit Mach-O executable")
    commands, command_bytes = struct.unpack_from("<II", data, 16)
    position = 32
    limit = position + command_bytes
    if limit > len(data):
        raise ValueError("truncated Mach-O load commands")
    result = {}
    for _ in range(commands):
        if position + 8 > limit:
            raise ValueError("truncated load command")
        command, size = struct.unpack_from("<II", data, position)
        if size < 8 or position + size > limit:
            raise ValueError("invalid load command size")
        if command == 0x19:  # LC_SEGMENT_64
            if size < 72:
                raise ValueError("truncated segment")
            count = struct.unpack_from("<I", data, position + 64)[0]
            if 72 + count * 80 > size:
                raise ValueError("truncated section table")
            for index in range(count):
                offset = position + 72 + index * 80
                name, segment, _, length, file_offset = struct.unpack_from(
                    "<16s16sQQI", data, offset
                )
                flags = struct.unpack_from("<I", data, offset + 64)[0]
                if flags & 0xFF in (1, 12, 18):  # zero-fill section types
                    continue
                if file_offset + length > len(data):
                    raise ValueError("section extends beyond file")
                key = (segment.rstrip(b"\0"), name.rstrip(b"\0"))
                if key in result:
                    raise ValueError("duplicate section")
                result[key] = hashlib.sha256(
                    data[file_offset : file_offset + length]
                ).digest()
        position += size
    if position != limit or not result:
        raise ValueError("invalid or empty section table")
    return result


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: verify-release-binary.py REFERENCE_BINARY PACKAGED_BINARY")
    try:
        reference = section_hashes(sys.argv[1])
        packaged = section_hashes(sys.argv[2])
        if reference != packaged:
            sys.exit("error: packaged code/data sections differ from the reference build")
        print(f"Release code/data verification passed: {len(reference)} sections match")
    except (OSError, ValueError, struct.error) as error:
        sys.exit(f"error: {error}")
