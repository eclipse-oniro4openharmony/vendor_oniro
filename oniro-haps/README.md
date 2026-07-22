# Oniro distribution HAPs

This directory is the self-contained home of the **Oniro-customized** apps that
ship on top of the stock OpenHarmony HAP set — the Oniro app store and
(optionally) the FlorisBoard IME. They are installed into the product image
**unconditionally**; there is no flavor switch to select.

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

## How they reach the image (no mirror patch, no flavor arg)

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
OpenHarmony mirror** — it is not patched, and no `gn` arg selects these HAPs.
Adding the set to another product is a one-line `sub_component` addition (set
`oniro_haps_part_name` to that product's part if it differs).

## No committed binaries — clone & build

The `.hap` files under `haps/` are **not committed** (`haps/.gitignore`). Only
source + provenance live in git, matching the Eclipse release model (no published
binaries; the consumer reproduces locally). Build them from the pinned remotes:

```bash
# 1. Clone each app from its pinned remote (oniro-haps.json) and build it
#    (writes haps/*.hap). REQUIRED before every product build below — the
#    product always depends on group("oniro_custom_haps").
bash vendor/oniro/oniro-haps/build-oniro-haps.sh

# 2. Build the image — it copies the just-built HAPs into system.img.
#    (Run from your OHOS build environment; if you build inside a container,
#    exec into it first, e.g. `docker exec -u root -w /home/openharmony/workdir <container> ...`.)
./build.sh --product-name hybris_generic --ccache
```

The driver clones each app's pinned `git`+`branch`+`sha` into
`out/oniro-haps/src/<app>` (cached, reused when already at the pinned sha), so the
build never depends on local working-tree state. This needs network (git clone +
`ohpm install` on a fresh clone). Flags: `--app <name>`, `--skip <name>`
(both repeatable), `--force-deps`, `--skip-deps`, `--sdk PATH`.

Because the product now **always** depends on this set, if you skip step 1 the
image build fails when ninja cannot find a HAP `source` under `haps/` (an
`ohos_prebuilt_etc` missing-input error) — re-run step 1 to fix it.

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

> **Release note:** these HAPs are now built into every `hybris_generic` image
> (no opt-in flavor). Their `git` sources for the app store and FlorisBoard are
> pinned in `oniro-haps.json`; the built binaries are not redistributed by
> Eclipse (the consumer reproduces them locally from the pinned source).
