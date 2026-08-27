# Oniro distribution HAPs

This directory is the self-contained home of the **Oniro-customized** apps that
ship on top of the stock OpenHarmony HAP set — the Oniro app store, the
FlorisBoard IME, and a rebuild of the platform **camera** carrying a rotation
fix. They are **opt-in** and **all or nothing**: one gn arg,
`oniro_install_custom_haps`, takes the whole set or none of it. The default
product build installs none of them.

> The system shell (SystemUI / Launcher / Settings) is provided by **SceneBoard**
> (`window_manager_use_sceneboard`), so the app store and FlorisBoard only *add*
> bundles — nothing stock is swapped out for those. (The camera is the exception
> and does replace a stock hap.) Earlier revisions carried
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

## How they reach the image

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

Each generated `ohos_prebuilt_etc` therefore carries the product's `part_name`
(`product_${device_name}` — `product_hybris_generic`, `product_x86_general`),
so it is gathered by that component. For the app store and FlorisBoard
`applications/standard/hap` stays a pristine OpenHarmony mirror — they only add
bundles, so nothing there needs patching. Adding the set to another product is a
one-line `sub_component` addition.

`BUILD.gn` generates targets only when `oniro_install_custom_haps` is true, so
with the default `false` the group is empty and the image gets no Oniro-built
HAP. The same arg drives `preinstall-config`, which regenerates
`install_list.json` from `oniro-haps.json` so BMS actually preinstalls the added
bundles (see `gen_preinstall_list.py`). The camera gets no new entry there: it
takes over a bundle the committed list already carries.

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

## The camera is different

`com.ohos.camera` is not an add-on. It is a rebuild of the platform's **own**
app from `applications/standard/camera`, pinned to a fork that fixes the
viewfinder controls and the saved JPEG being 90°/180° out of true. It rides the
same switch as everything else, but two keys in its descriptor entry are unique
to it:

* **`"self_signed": true`** — keep the app's own `signingConfig` instead of the
  driver's null-and-resign path, which would change both the certificate and the
  provision profile. `com.ohos.camera` has an `app_signature` entry in
  `install_list_capability.json` granting `allowAppUsePrivilegeExtension`, and
  its committed `camera.p7b` is an `os_integration` profile carrying a Camera
  distribution certificate that the generic template cannot reproduce. The app's
  own material works off-host and yields the chain the stock hap has (leaf
  *OpenHarmony Application Release*,
  `0716E4E8C9B8CEEF6A974CD2289D5C4C668A5B41FA5DF8C0542DCB72602371F5`). Re-check
  that chain after changing anything here: get it wrong and bms refuses the hap
  at first boot, the way it does the sceneboard `CallUI.hap`.

* **A per-app `build_cmd`** — the app is multi-module (only `phone` ships) and
  must be built in **release** mode; a debug build carries `ets/sourceMaps.map`
  and an unoptimised `modules.abc` and comes out ~9 MB larger than the stock hap.

Being a replacement rather than an addition also means it is the one app that
patches the mirror: it installs `app/com.ohos.camera/Camera.hap`, the same path
as the stock `camera_hap`, so exactly one of the two must be active or ninja sees
two rules writing one file. `oniro_install_custom_haps` drops the stock target in
`applications/standard/hap/BUILD.gn` (a product-scoped one-liner). **With the arg
off, the stock — rotation-buggy — camera ships.**

## Signing note

The app store requests privileged permissions (`INSTALL_BUNDLE`, etc.) and calls
system APIs, so `oniro-haps.json` pins its `apl` to `system_core`. The driver
signs any `system_basic`/`system_core` app with an `hos_system_app` provision
profile (promoted from the stock `hos_normal_app` template) — without that the
HAP installs but is flagged non-system and its system-API calls are rejected with
*"non-system app calling system api"*. See `build-oniro-haps.sh::sign_hap`.

Apps with `"self_signed": true` bypass all of this and keep their own
`signingConfig` — see [The camera is different](#the-camera-is-different).

## Provenance (Eclipse Bucket 4a)

[`oniro-haps.json`](oniro-haps.json) **is** the provenance: per app it pins the
`git` repo, `branch`, `sha`, `apl`, `license`, and the module→HAP mapping; the
top-level `build_cmd` records the build command (an app may override it with its
own `build_cmd`). Every app embeds its own `signingConfig`, and for all but the
`self_signed` ones it is **not** used — the driver nulls it, builds the unsigned
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
> image, including the app store's GPL-3.0-or-later obligations. Since the set is
> all-or-nothing, that applies even if the camera is the only part you wanted.
