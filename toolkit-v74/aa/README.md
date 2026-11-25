# Android Auto on v74 with the original hub - deploy kit

Working Android Auto over the **stock Desay hub** on firmware `MAZ_CMU-150_74.00.324`,
no hardware hub swap. Full explanation, install steps and command reference:
**[docs/ANDROID-AUTO-V74.md](../../docs/ANDROID-AUTO-V74.md)**.

| Path | What |
|---|---|
| `scripts/` | the 5 on-car scripts (`aa-early.sh`, `aa-guard.sh`, `aa-install.sh`, `aa-status.sh`, `aa-uninstall.sh`) |
| `MANIFEST.md5` | md5 of both payloads + the 5 scripts; `aa-install.sh` refuses any deviation |
| `tools/make-patched.py` | builds the two `.patched` payloads from **your own** stock `.so` files (md5-checked in and out) |
| `tools/make-manifest.sh` | regenerates `MANIFEST.md5` (only needed if you change a script) |
| `tests/run-sandbox-tests.sh` | host-side sandbox test (248 checks, BusyBox sh + dash) |
| `evidence/` | objdump diffs of the two 1-byte patches + the `usb_drivers.sh` hook diff |
| `payload/` | empty in the repo - `make-patched.py` writes the payloads here |

**No Mazda/JCI binaries are shipped** - generate the payloads yourself:

```sh
python3 tools/make-patched.py svcjciusbmgr.so blmjciaapa.so      # -> payload/
```

The scripts are shipped **unchanged** from the hardware-tested version, so their
comments and messages are in Dutch. Do not edit them unless you also regenerate
`MANIFEST.md5`.

Sandbox test (needs the generated payload, a stock `svcjciusbmgr.so` and the stock
`/jci/scripts/usb_drivers.sh` from your CMU):

```sh
SUT="busybox sh" sh tests/run-sandbox-tests.sh stock-svcjciusbmgr.so stock-usb_drivers.sh
SUT=dash         sh tests/run-sandbox-tests.sh stock-svcjciusbmgr.so stock-usb_drivers.sh
```

**Before any firmware update:** `sh /data_persist/dev/aa/aa-uninstall.sh --restore-hook`.
