#!/usr/bin/env python3
"""Carve ARM ELF binaries out of a CMU rootfs image and list their symbols.

Usage: python3 -I elfsym.py <rootfs-image> <elf-offset...>

The rootfs image is a flat MAST container (NOT a squashfs): ELF binaries can
be carved directly by scanning for the \\x7fELF magic. For each offset given,
parse the ELF section headers and dynamic symbol table, then print the
undefined symbols matching VIM/VBS/SPI/CAN/SEND/MSG/VIP -- enough to map the
D-Bus -> VBS -> mod_can -> vim_app -> SPI -> VIP chain from symbol names.

Read-only; run with python3 -I on untrusted firmware data.
"""
import struct, sys

img = sys.argv[1]
data = open(img, 'rb').read()

def parse_elf(e):
    ei = data[e:e + 52]
    assert ei[:4] == b'\x7fELF'
    shoff = struct.unpack('<I', ei[32:36])[0]
    shentsize, shnum = struct.unpack('<HH', ei[46:50])
    shstrndx = struct.unpack('<H', ei[50:52])[0]
    secs = []
    for i in range(shnum):
        s = data[e + shoff + i * shentsize:e + shoff + (i + 1) * shentsize]
        if len(s) < 40:
            continue
        vals = struct.unpack('<IIIIIIIIII', s)
        secs.append(dict(zip(['name', 'type', 'flags', 'addr', 'off', 'size',
                              'link', 'info', 'align', 'entsize'], vals)))
    if shstrndx < len(secs):
        shstr = secs[shstrndx]
        strtab = data[e + shstr['off']:e + shstr['off'] + shstr['size']]
        for s in secs:
            s['nm'] = strtab[s['name']:].split(b'\0')[0].decode('ascii', 'replace')
    else:
        for s in secs:
            s['nm'] = '?'
    return secs

def dynsyms(e, secs):
    out = []
    for s in secs:
        if s['nm'] in ('.dynsym', '.symtab') and s['entsize']:
            strsec = secs[s['link']] if s['link'] < len(secs) else None
            tab = data[e + strsec['off']:e + strsec['off'] + strsec['size']] if strsec else b''
            n = s['size'] // s['entsize']
            for i in range(n):
                off = s['off'] + i * s['entsize']
                rec = data[e + off:e + off + s['entsize']]
                if len(rec) < 16:
                    continue
                nm, info, other, shndx, value, size = struct.unpack('<IIBBHH', rec[:14])
                name = tab[nm:].split(b'\0')[0].decode('ascii', 'replace') if nm < len(tab) else '?'
                out.append((name, shndx, info))
    return out

for arg in sys.argv[2:]:
    e = int(arg, 0)
    secs = parse_elf(e)
    ds = dynsyms(e, secs)
    und = [n for n, s, i in ds if s == 0]
    print(f"== {e:#x}: {len(ds)} syms, {len(und)} undefined")
    keys = ['VIM', 'VBS', 'SPI', 'CAN', 'SEND', 'MSG', 'VIP']
    print('   interesting undefined:', [u for u in und if any(k in u.upper() for k in keys)][:40])
