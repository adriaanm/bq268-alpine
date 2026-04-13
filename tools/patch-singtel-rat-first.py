#!/usr/bin/env python3
"""One-shot: patch /sd/rat_acq_order in singtel_sg.mbn to put LTE first."""
import struct, hashlib, sys

src = '/home/adriaan/bq268-alpine/rootfs/files/usr/share/cellular-mcfg/singtel_sg.mbn'
dst = '/tmp/mcfg_out/singtel_sg_lte_first.mbn'

d = bytearray(open(src, 'rb').read())
mcfg_off = 0x2000
assert d[mcfg_off:mcfg_off+4] == b'MCFG'
num_items = struct.unpack_from('<I', d, mcfg_off+8)[0]
pos = mcfg_off + 16
sub_len = struct.unpack_from('<H', d, pos+2)[0]
pos += 4 + sub_len

found = False
for i in range(num_items):
    if pos + 8 > len(d): break
    item_len, item_type = struct.unpack_from('<IB', d, pos)[:2]
    if item_type == 2:
        bpos = pos + 8
        m1, plen = struct.unpack_from('<HH', d, bpos)
        if m1 == 0x0001:
            path = bytes(d[bpos+4:bpos+4+plen]).rstrip(b'\x00').decode('ascii', 'replace')
            dpos = bpos + 4 + plen
            m2, dlen = struct.unpack_from('<HH', d, dpos)
            if m2 == 0x0002 and path == '/sd/rat_acq_order':
                data_off = dpos + 4
                data = bytes(d[data_off:data_off+dlen])
                print(f'Found at 0x{data_off:x}: {data.hex()}')
                # Original: 07 03 e7 00 05 09 05 03 02 04  (UMTS-first)
                # Want:     07 03 e7 00 09 05 05 03 02 04  (LTE-first)
                # Byte 4 (0x05=UMTS) and byte 5 (0x09=LTE) swap
                assert data == bytes.fromhex('0703e700050905030204'), f'unexpected data: {data.hex()}'
                new_data = bytes.fromhex('0703e700090505030204')
                d[data_off:data_off+dlen] = new_data
                print(f'Patched to:   {new_data.hex()}')
                found = True
                break
    pos += item_len

assert found, 'rat_acq_order not found'

# Rehash segments
# Segment 0: ELF header + PHs at 0..0x94
# Segment 2 (MCFG): from 0x2000 onwards
# Find MCFG segment end by walking items again (data unchanged in length)
pos = mcfg_off + 16 + 4 + sub_len
for i in range(num_items):
    item_len = struct.unpack_from('<I', d, pos)[0]
    pos += item_len
mcfg_end = pos
mcfg_bytes = bytes(d[mcfg_off:mcfg_end])

hash0 = hashlib.sha256(bytes(d[0:0x94])).digest()
hash1 = b'\x00' * 32
hash2 = hashlib.sha256(mcfg_bytes).digest()

hash_data_off = 0x1000 + 40
d[hash_data_off:hash_data_off+32] = hash0
d[hash_data_off+32:hash_data_off+64] = hash1
d[hash_data_off+64:hash_data_off+96] = hash2

open(dst, 'wb').write(d)
print(f'Written: {dst} ({len(d)} bytes)')
