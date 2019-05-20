#!/usr/bin/env python
import sys
import ctypes
import base64
import struct
from pysss_murmur import murmurhash3

def calculate_range(domain_sid, slice_num = -1):
    idmap_lower = 200000
    idmap_upper = 2000200000
    rangesize = 200000
    autorid_mode = True
    new_slice = 0

    max_slices = (idmap_upper - idmap_lower) / rangesize;

    if slice_num != -1:
        new_slice = slice_num;
        min_id = (rangesize * new_slice) + idmap_lower;
        max_id = min_id + rangesize - 1;
    else:
        if autorid_mode:
            orig_slice = 0
        else:
            hash_val = murmurhash3(domain_sid, len(domain_sid), 0xdeadbeef);
            new_slice = hash_val % max_slices;
            orig_slice = new_slice;

    min_id = (rangesize * new_slice) + idmap_lower;
    max_id = min_id + rangesize - 1;

    return ({ "min": min_id, "max": max_id, "first_rid": 0, "slice_num": new_slice })

def comp_id(range, rid):
    if rid >= range["first_rid"] and (ctypes.c_uint(-1).value - range["min"]) > (rid - range["first_rid"]):
        id = range["min"] + rid - range["first_rid"]
        if id <= range["max"]:
            return id
    return -1


def convert(binary):
    version = struct.unpack('B', binary[0:1])[0]
    # I do not know how to treat version != 1 (it does not exist yet)
    assert version == 1, version
    length = struct.unpack('B', binary[1:2])[0]
    authority = struct.unpack(b'>Q', b'\x00\x00' + binary[2:8])[0]
    string = 'S-%d-%d' % (version, authority)
    binary = binary[8:]
    assert len(binary) == 4 * length
    for i in range(length):
        value = struct.unpack('<L', binary[4*i:4*(i+1)])[0]
        string += '-%d' % value
    return string

def idmap(objectsid):
    domain_sid, rid = convert(base64.b64decode(objectsid)).rsplit('-',1)
    print(comp_id(calculate_range(domain_sid, -1), int(rid)))

if __name__ == "__main__":
    idmap(sys.argv[1])
