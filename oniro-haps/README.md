# Oniro distribution-flavor HAPs

This directory is the self-contained home of the **Oniro-customized** system
applications — SystemUI (+ its sub-module HAPs), Launcher, Settings, the Oniro
app store, and (optionally) the FlorisBoard IME. Selecting the **Oniro UI
flavor** at build time swaps the stock OpenHarmony HAPs in
`applications/standard/hap` for the ones installed here.

```
oniro-haps/
  oniro-haps.json        descriptor + Bucket-4a provenance (committed)
  build-oniro-haps.sh    clones each app from its pinned remote and builds it
  BUILD.gn               group("oniro_custom_haps") prebuilt_etc targets
  haps/                  built HAPs + SHA256SUMS (gitignored — not committed)
```

## No committed binaries — clone & build

The `.hap` files under `haps/` are **not committed** (`haps/.gitignore`). Only
source + provenance live in git, matching the Eclipse release model (no published
binaries; the consumer reproduces locally). Build them from the pinned remotes:

```bash
# 1. Clone each app from its pinned remote (oniro-haps.json) and build (writes haps/*.hap):
bash vendor/oniro/oniro-haps/build-oniro-haps.sh

# 2. Build the image — it copies the just-built HAPs into system.img:
sudo docker exec -u root -w /home/openharmony/workdir 0bb7ce2c1ccc \
    ./build.sh --product-name hybris_generic --ccache
```

The driver clones each app's pinned `git`+`branch`+`sha` into
`out/oniro-haps/src/<app>` (cached, reused when already at the pinned sha), so the
build never depends on local working-tree state. This needs network (git clone +
`ohpm install` on a fresh clone). Flags: `--app <name>`, `--no-appstore`,
`--no-floris`, `--force-deps`, `--skip-deps`, `--sdk PATH`.

If you skip step 1, the build fails when ninja cannot find a HAP `source` under
`haps/` (an `ohos_prebuilt_etc` missing-input error) — re-run step 1 to fix it.

## Choosing the flavor

A `gn` arg, declared in `applications/standard/hap/BUILD.gn`, selects the UI:

| `oniro_ui_flavor` | Result |
|---|---|
| `oniro` (default for `hybris_generic` / `x86_general`) | Oniro custom HAPs from this dir |
| `stock` | Upstream OpenHarmony HAPs in `applications/standard/hap` (no step 1 needed) |
| `default` (other products) | Resolves to `stock` |

```bash
./build.sh --product-name hybris_generic --ccache --gn-args 'oniro_ui_flavor="stock"'
```

FlorisBoard is gated by `oniro_include_florisboard` (default `true`); pass
`--gn-args 'oniro_include_florisboard=false'` (and the driver's `--no-floris`) to
omit it. It is marked `optional` in the descriptor so the driver does not abort
when it is skipped.

## Provenance (Eclipse Bucket 4a)

[`oniro-haps.json`](oniro-haps.json) **is** the provenance: per app it pins the
`git` repo, `branch`, `sha`, `apl`, `license`, and the module→HAP mapping; the
top-level `build_cmd` records the build command. Every app embeds its own
`signingConfig`, but it is **not** used — the driver nulls it, builds the unsigned
HAP, and signs deterministically with the public OpenHarmony test keys
(`developtools/hapsigner`, password `123456`) at the app's `apl`, so the result is
host-independent. No per-HAP sha256 is committed (a signed HAP carries a hapsigner
nonce and is not bit-reproducible, and Eclipse does not redistribute it); the
reproducible invariant is *pinned source sha + build-cmd*. `haps/SHA256SUMS`
(gitignored) records the checksums of a given local build for verification.

> **Release note:** the `git` for systemui/launcher/settings/florisboard currently
> points at personal `frankplus/*` forks. Re-point to
> `eclipse-oniro4openharmony/*` and re-pin `sha` before tagging. (`f-oh` is already
> on the Eclipse org.)

> `SystemUI-ScreenLock.hap` is **not** part of this set — it stays stock (from
> `applications/standard/screenlock`) and remains in `applications/standard/hap`.
