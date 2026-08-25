# Oniro distribution HAPs

This directory is the self-contained home of the **Oniro-customized** apps that
ship on top of the stock OpenHarmony HAP set — the Oniro app store and
(optionally) the FlorisBoard IME. They are **opt-in**: the default product
build installs none of them, and `oniro_install_custom_haps=true` turns the set
on.

> The system shell (SystemUI / Launcher / Settings) is provided by **SceneBoard**
> (`window_manager_use_sceneboard`), so this set only *adds* the app store and
> FlorisBoard — nothing stock is swapped out. Earlier revisions carried
> Oniro-customized SystemUI / Launcher / Settings HAPs and reached into
> `applications/standard/hap` via a gn `oniro_ui_flavor` switch; both were dropped
> once the tree moved to SceneBoard.

```
oniro-haps/
  oniro-haps.json        SINGLE SOURCE OF TRUTH: descriptor + Bucket-4a provenance
  build-oniro-haps.sh    clones each app from its pinned remote and builds it
  BUILD.gn               generates one prebuilt_etc per descriptor module
                         (read_file of oniro-haps.json) + group("oniro_custom_haps")
  haps/                  built HAPs + SHA256SUMS (gitignored — not committed)
```

The HAP set is defined **once**, in `oniro-haps.json`: both the driver script
and `BUILD.gn` read it, so adding/removing an app or module is a
descriptor-only change.

## How they reach the image (no mirror patch)

`BUILD.gn` here exposes `group("oniro_custom_haps")`, and the product component
lists it in its `bundle.json` `sub_component` — exactly like `preinstall-config`:

```jsonc
// vendor/oniro/hybris_generic/bundle.json
"sub_component": [
  "//vendor/oniro/hybris_generic/preinstall-config:preinstall-config",
  "//vendor/oniro/oniro-haps:oniro_custom_haps",
  ...
]
```

Each generated `ohos_prebuilt_etc` therefore carries the product's
`part_name` (`oniro_haps_part_name`, default `product_hybris_generic`) so it is
gathered by that component. `applications/standard/hap` stays a **pristine
OpenHarmony mirror** — it is not patched. Adding the set to another product is a
one-line `sub_component` addition (set `oniro_haps_part_name` to that product's
part if it differs).

`BUILD.gn` generates those targets only when `oniro_install_custom_haps` is
true, so with the default `false` the group is empty and the image gets no
Oniro-built HAP. The switch also drives `preinstall-config`, which regenerates
`install_list.json` from `oniro-haps.json` so BMS actually preinstalls the
bundles when you opt in (see `gen_preinstall_list.py`).

Why off by default: these apps are built from sources outside this repository
under licences that differ from the product's own — the app store is
**GPL-3.0-or-later**. Shipping them in the default image would put that
obligation on every consumer of the image, so the release ships the stock HAP
set and leaves the choice to whoever builds.

## No committed binaries — clone & build

The `.hap` files under `haps/` are **not committed** (`haps/.gitignore`). Only
source + provenance live in git, matching the Eclipse release model (no published
binaries; the consumer reproduces locally). Build them from the pinned remotes:

```bash
# 1. Clone each app from its pinned remote (oniro-haps.json) and build it
#    (writes haps/*.hap). REQUIRED whenever you opt in below — with the HAPs
#    missing, ninja fails on the prebuilt_etc `source` input.
bash vendor/oniro/oniro-haps/build-oniro-haps.sh

# 2. Build the image WITH the set — it copies the just-built HAPs into
#    system.img and adds their preinstall entries.
#    (Run from your OHOS build environment; if you build inside a container,
#    exec into it first, e.g. `docker exec -u root -w /home/openharmony/workdir <container> ...`.)
./build.sh --product-name hybris_generic --ccache \
    --gn-args "oniro_install_custom_haps=true"

# A plain build omits the set entirely and needs neither step 1 nor the arg:
./build.sh --product-name hybris_generic --ccache
```

The driver clones each app's pinned `git`+`branch`+`sha` into
`out/oniro-haps/src/<app>` (cached, reused when already at the pinned sha), so the
build never depends on local working-tree state. This needs network (git clone +
`ohpm install` on a fresh clone). Flags: `--app <name>`, `--skip <name>`
(both repeatable), `--force-deps`, `--skip-deps`, `--sdk PATH`.

Skipping step 1 while passing the gn arg fails the image build: ninja cannot
find a HAP `source` under `haps/` (an `ohos_prebuilt_etc` missing-input error)
— re-run step 1 to fix it. Step 1 *without* the arg is a no-op for the image.

Apps marked `"optional": true` in the descriptor (currently only FlorisBoard)
are gated by the `oniro_include_florisboard` gn arg (default `true`); pass
`--gn-args 'oniro_include_florisboard=false'` (and the driver's
`--skip florisboard`) to omit them.

## Signing note

The app store requests privileged permissions (`INSTALL_BUNDLE`, etc.) and calls
system APIs, so `oniro-haps.json` pins its `apl` to `system_core`. The driver
signs any `system_basic`/`system_core` app with an `hos_system_app` provision
profile (promoted from the stock `hos_normal_app` template) — without that the
HAP installs but is flagged non-system and its system-API calls are rejected with
*"non-system app calling system api"*. See `build-oniro-haps.sh::sign_hap`.

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

> **Release note:** the default `hybris_generic` image contains none of these
> HAPs, so the Eclipse release redistributes no Oniro-built HAP and none of the
> licences below apply to it. Their `git` sources are pinned in
> `oniro-haps.json` purely as provenance. Opting in with
> `oniro_install_custom_haps=true` makes *you* the distributor of the resulting
> image, including the app store's GPL-3.0-or-later obligations.
