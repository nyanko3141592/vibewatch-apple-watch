#!/usr/bin/env python3
import hashlib
import pathlib
import re
import struct

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_MAP_SHA256 = "fab0001cf1e2da45f805ee9bb3957b833af341300b10f76d2111f15f9d0bbcad"
UF2_MAGIC = (0x0A324655, 0x9E5D5157)


def report_map() -> bytes:
    source = (ROOT / "include/vibe_hid.h").read_text()
    match = re.search(r"reportMap\[\]\s*=\s*\{(.*?)\};", source, re.S)
    assert match, "reportMap was not found"
    return bytes(int(value, 16) for value in re.findall(r"0x([0-9A-Fa-f]{2})", match.group(1)))


def uf2_addresses() -> list[int]:
    data = (ROOT / "VibeWatch-BLE-Micro-Pro.uf2").read_bytes()
    assert len(data) % 512 == 0, "UF2 is not made of 512-byte blocks"
    addresses = []
    for offset in range(0, len(data), 512):
        header = struct.unpack_from("<8I", data, offset)
        assert header[:2] == UF2_MAGIC, "invalid UF2 magic"
        addresses.append(header[3])
    return addresses


descriptor = report_map()
assert len(descriptor) == 200
assert hashlib.sha256(descriptor).hexdigest() == EXPECTED_MAP_SHA256
assert b"\x06\x00\xff\x09\x01\xa1\x01\x85\x06" in descriptor
assert b"\x75\x08\x95\x3f\x81\x02" in descriptor

addresses = uf2_addresses()
assert min(addresses) == 0x26000, hex(min(addresses))
assert max(addresses) < 0xF0000, hex(max(addresses))

print("PASS: exact 200-byte HID map, report ID 6 x 63 bytes, UF2 app origin 0x26000")
