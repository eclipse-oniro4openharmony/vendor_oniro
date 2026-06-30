# Oniro Vendor / Product Configuration

This repository contains the product-level (vendor) configuration for the
products shipped by the Oniro Project. It defines what each product is made of:
the system parameters, init configuration, partition/fstab layout, HDF device
configuration, preinstalled apps, and the product build definition that ties the
board and SoC adaptations together.

## Targets

### `hybris_generic` — Volla devices (native OpenHarmony)

Product configuration for running **OpenHarmony natively** on Volla hardware
(Volla X23, Volla Tablet) on top of the device's Android vendor stack via
**libhybris**. Includes `product.gni`, init/boot configuration, fstab, HDF
config, the boot animation, and preinstall configuration.

The full bring-up and boot architecture are documented in the board repository,
under `device/board/oniro/docs/hybris_generic/README.md`.

### `x86_general` — QEMU / x86 emulator

Product configuration for the Oniro emulator target, including the source-patch
hooks (`x86_general/hook/`) applied before building. See the board repository's
README for the emulator build flow.

## `oniro-haps` — reproducible Oniro distribution flavor

`oniro-haps/` builds the Oniro-customized system app set (SystemUI, Launcher,
Settings, the Oniro app store, and the FlorisBoard IME port) **from source**.
The HAP binaries are not committed; `oniro-haps/build-oniro-haps.sh` clones each
app at the git revision pinned in `oniro-haps/oniro-haps.json` (which records
source repo, commit, build command, and license for each) and builds it, so the
flavor is reproducible. See [`oniro-haps/README.md`](./oniro-haps/README.md).

## Building

These repositories are assembled into a full Oniro source tree via the Oniro
manifest; you do not clone them individually:

```bash
repo init -u https://github.com/eclipse-oniro4openharmony/manifest.git -b OpenHarmony-6.1-Release -m oniro.xml --no-repo-verify
repo sync -c
repo forall -c 'git lfs pull'
```

## License

Released under the Apache License, Version 2.0. See [LICENSE](./LICENSE) and
[NOTICE](./NOTICE).
