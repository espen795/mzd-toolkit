# VIP firmware reverse-engineering helpers

Small, dependency-free Python helpers used to analyse the **VIP coprocessor
firmware** (Renesas M16C, R5F35MCEJFB) found inside the CMU firmware images.
No firmware content is embedded in these files; they operate on an image you
supply as an argument. See `docs/VIP-FIRMWARE-RE.md` for the findings.

All scripts are pure Python 3 (standard library only), run with `python3 -I`,
and are read-only with respect to the input image.

## Files

| File | What |
|---|---|
| `srec_build.py <image> <outdir>` | Parse the S-record region (default 0x200-0x1C2000) of a raw firmware image into flat per-segment binaries + a `segments.json` index. The VIP application lands in e.g. `S2_0C0000_xxxxxx.bin` (load base 0xC0000). |
| `m16c_scan.py <bin> [base]` | Scan a flat M16C binary for 16-bit little-endian values in the CAN SFR window 0xD300-0xD800 (as they appear as MOV abs16 operands), plus opcode-pattern histograms for the candidate write encodings. |
| `m16c_movscan.py <bin> [base]` | Pattern-scan for MOV instructions (opcodes 0x8C/0x89 and the generic `op aw16` / `op b aw16` forms) whose abs16 operand lands in 0xD000-0xDFFF; prints an opcode histogram so you can see which encoding the Renesas NC30 compiler actually used. |
| `m16c_disasm.py <bin> [base]` | Minimal linear M16C/60 disassembler (length table + JSR/JMP/abs16 annotations). Not a complete disassembler -- use it to follow control flow and dump bytes around a site. |
| `m16c_decode.py <bin> [base]` | Context dump around a list of candidate CAN-SFR access sites (bytes before/after with annotations). |
| `m16c_hexdump.py <bin> <addr...>` | Hexdump a window around one or more absolute addresses. |
| `elfsym.py <image> <elf-offset...>` | Carve ARM ELF binaries out of a MAST-container rootfs image (scan for `\x7fELF`), parse section headers and dynamic symbols, and list the undefined symbols matching VIM/VBS/SPI/CAN/SEND/MSG/VIP. |

## Reproducing the CAN-TX analysis

```sh
# 1. build the flat VIP_APP binary from the raw firmware image
python3 -I srec_build.py cmu_resources_raw.img /tmp/out
# 2. CAN SFR address scan
python3 -I m16c_scan.py /tmp/out/seg/S2_0C0000_03567C.bin 0xC0000
# 3. MOV-operand pattern scan
python3 -I m16c_movscan.py /tmp/out/seg/S2_0C0000_03567C.bin 0xC0000
# 4. hexdump around a site of interest
python3 -I m16c_hexdump.py /tmp/out/seg/S2_0C0000_03567C.bin 0xD0A3F
```

## Known limitations

- GNU binutils has no `m16c` target and the common third-party M16C toolchains
  are ARM-only, so a full M16C disassembly was not available; the scripts above
  are targeted opcode/address-pattern analysers, not a complete disassembler.
  Register/SFR semantics therefore remain "probable" (based on the M16C/60
  SFR map) rather than proven instruction-by-instruction.
- The rootfs image is a flat MAST container, NOT a squashfs; carve ELF binaries
  with an `\x7fELF` scan (see `elfsym.py`) or via the LDIR/JMET index.
