#!/usr/bin/env bash
#
# build-oniro-haps.sh — build the Oniro distribution-flavor HAP set from pinned source.
#
# Copyright (c) 2026 Eclipse Oniro for OpenHarmony contributors.
# SPDX-License-Identifier: Apache-2.0
#
# The Oniro-customized system HAPs (SystemUI*, Launcher*, Settings, the Oniro app
# store, FlorisBoard) are NOT committed as binaries. This script CLONES each app
# from its pinned remote git repo (git+branch+sha in oniro-haps.json) into
# out/oniro-haps/src/<app> (cached, reused at the pinned sha) and builds it, so the
# release is reproducible from upstream. The committed oniro-haps.json IS the
# Bucket-4a provenance (source-repo / source-sha / build-cmd / license); this
# script additionally writes haps/SHA256SUMS (gitignored) for local verification.
#
# Two-step flow (oniro flavor):
#   1. bash vendor/oniro/oniro-haps/build-oniro-haps.sh
#   2. ./build.sh --product-name hybris_generic --ccache     (copies the HAPs)
# The stock flavor needs no step 1 (it uses the upstream applications/standard/hap
# prebuilts) — see README.md.
#
# Signing is deterministic and host-independent: the driver nulls each app's
# embedded signingConfig (whose encrypted passwords are tied to per-machine DevEco
# material and fail off-host), builds the UNSIGNED hap, then signs with the public
# OpenHarmony test keys (developtools/hapsigner, password 123456) at the app's apl.
# Needs network (git clone + ohpm install on a fresh clone).

set -euo pipefail

# --- locations ---------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"            # vendor/oniro/oniro-haps -> tree root
DESC="${SCRIPT_DIR}/oniro-haps.json"
OUT_DIR="${SCRIPT_DIR}/haps"
SHASUMS="${OUT_DIR}/SHA256SUMS"
SRC_CACHE="${ROOT}/out/oniro-haps/src"   # cloned sources (gitignored out/)

# --- defaults / flags --------------------------------------------------------
SDK="${OHOS_SDK_HOME:-$HOME/setup-ohos-sdk/linux}"
ONLY_APPS=()
NO_APPSTORE=0
NO_FLORIS=0
FORCE_DEPS=0
SKIP_DEPS=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --app NAME      Build only this app (repeatable). Default: all in oniro-haps.json
  --no-appstore   Skip the Oniro app store (f-oh)
  --no-floris     Skip FlorisBoard
  --force-deps    Always run 'ohpm install' even if oh_modules/ exists
  --skip-deps     Never run 'ohpm install' (only for a warm cached clone)
  --sdk PATH      OpenHarmony SDK base dir (default: \$OHOS_SDK_HOME or
                  \$HOME/setup-ohos-sdk/linux)
  -h, --help      This help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --app)         ONLY_APPS+=("$2"); shift 2 ;;
    --no-appstore) NO_APPSTORE=1; shift ;;
    --no-floris)   NO_FLORIS=1; shift ;;
    --force-deps)  FORCE_DEPS=1; shift ;;
    --skip-deps)   SKIP_DEPS=1; shift ;;
    --sdk)         SDK="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# --- helpers -----------------------------------------------------------------
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_rst=$'\033[0m'
log()  { echo "${c_grn}[oniro-haps]${c_rst} $*"; }
warn() { echo "${c_yel}[oniro-haps] WARN:${c_rst} $*" >&2; }
die()  { echo "${c_red}[oniro-haps] ERROR:${c_rst} $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
need jq; need git; need hvigorw; need node; need sha256sum; need java

HVIGORW="$(command -v hvigorw)"          # global wrapper; ignore broken project ./hvigorw
NODE_DIR="$(dirname "$(dirname "$(command -v node)")")"
[ -d "$SDK" ] || die "OpenHarmony SDK not found at: $SDK (set --sdk or \$OHOS_SDK_HOME)"

SIGN_DIST="${ROOT}/developtools/hapsigner/dist"
[ -f "${SIGN_DIST}/hap-sign-tool.jar" ] || die "hapsigner not found: ${SIGN_DIST}/hap-sign-tool.jar"
BUILD_CMD="$(jq -r '.build_cmd' "$DESC")"

want_app() {
  local name="$1"
  if [ "${#ONLY_APPS[@]}" -gt 0 ]; then
    local a; for a in "${ONLY_APPS[@]}"; do [ "$a" = "$name" ] && return 0; done
    return 1
  fi
  [ "$name" = "appstore" ] && [ "$NO_APPSTORE" -eq 1 ] && return 1
  [ "$name" = "florisboard" ] && [ "$NO_FLORIS" -eq 1 ] && return 1
  return 0
}

# Clone (or reuse) the pinned source for app $idx -> sets SRCDIR.
prepare_clone() {  # idx
  local idx="$1" name git_url branch sha dir
  name="$(jq -r ".apps[$idx].name" "$DESC")"
  git_url="$(jq -r ".apps[$idx].git" "$DESC")"
  branch="$(jq -r ".apps[$idx].branch // \"\"" "$DESC")"
  sha="$(jq -r ".apps[$idx].sha // \"\"" "$DESC")"
  dir="${SRC_CACHE}/${name}"

  if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$sha" ]; then
    log "reuse clone $name @ ${sha:0:12}"
  else
    rm -rf "$dir"; mkdir -p "$SRC_CACHE"
    log "clone $git_url (${branch:-default}) ..."
    if [ -n "$branch" ]; then
      git clone --branch "$branch" "$git_url" "$dir" >/dev/null 2>&1 \
        || die "$name: git clone failed: $git_url (branch $branch)"
    else
      git clone "$git_url" "$dir" >/dev/null 2>&1 || die "$name: git clone failed: $git_url"
    fi
    if [ -n "$sha" ]; then
      git -C "$dir" checkout --quiet --detach "$sha" 2>/dev/null \
        || die "$name: pinned sha ${sha:0:12} not found on $git_url (is branch '$branch' pushed?)"
    fi
  fi
  SRCDIR="$dir"
}

# Build a hvigor app UNSIGNED. The repos' encrypted-password signingConfigs are
# tied to per-machine DevEco material and fail off-host, so we null the product
# signingConfig (hvigor then skips SignHap and emits -unsigned.hap for every
# module) and sign deterministically afterwards.
build_hvigor_app() {  # src_abs
  local src="$1"
  local bp="${src}/build-profile.json5" bak rc=0
  bak="$(mktemp)"; cp "$bp" "$bak"
  sed -i -E 's/("signingConfig"[[:space:]]*:[[:space:]]*)"[^"]*"/\1""/g' "$bp"
  if ! ( cd "$src"
         printf 'sdk.dir=%s\nnodejs.dir=%s\n' "$SDK" "$NODE_DIR" > local.properties
         if [ "$SKIP_DEPS" -eq 0 ] && { [ "$FORCE_DEPS" -eq 1 ] || [ ! -d "$src/oh_modules" ]; }; then
           log "ohpm install in $(basename "$src") ..."
           ohpm install >/dev/null 2>&1 || warn "ohpm install reported errors (continuing if oh_modules present)"
         fi
         log "hvigor assembleHap (unsigned) in $(basename "$src") ..."
         # shellcheck disable=SC2086
         "$HVIGORW" $BUILD_CMD >/dev/null ); then
    rc=1
  fi
  cp "$bak" "$bp"; rm -f "$bak"
  [ "$rc" -eq 0 ] || die "$(basename "$src") hvigor build failed (see output above)"
}

# Sign an unsigned HAP with the public OpenHarmony test keys at the given apl.
sign_hap() {  # unsigned_hap  out_hap  bundle  apl
  local unsigned="$1" out="$2" bundle="$3" apl="$4" w rc=0
  w="$(mktemp -d)"
  cp "${SIGN_DIST}/hap-sign-tool.jar" "${SIGN_DIST}/OpenHarmony.p12" \
     "${SIGN_DIST}/OpenHarmonyApplication.pem" "${SIGN_DIST}/OpenHarmonyProfileRelease.pem" \
     "${SIGN_DIST}/UnsgnedReleasedProfileTemplate.json" "$w/"
  sed -e "s/com.OpenHarmony.app.test/${bundle}/g" -e "s/\"normal\"/\"${apl}\"/g" \
      "$w/UnsgnedReleasedProfileTemplate.json" > "$w/profile.json"
  ( cd "$w"
    java -jar hap-sign-tool.jar sign-profile \
      -keyAlias "openharmony application profile release" -signAlg SHA256withECDSA \
      -mode localSign -profileCertFile OpenHarmonyProfileRelease.pem -inFile profile.json \
      -keystoreFile OpenHarmony.p12 -outFile profile.p7b -keyPwd 123456 -keystorePwd 123456 >/dev/null
    java -jar hap-sign-tool.jar sign-app \
      -keyAlias "openharmony application release" -signAlg SHA256withECDSA \
      -mode localSign -appCertFile OpenHarmonyApplication.pem -profileFile profile.p7b \
      -inFile "$unsigned" -keystoreFile OpenHarmony.p12 -outFile "$out" \
      -keyPwd 123456 -keystorePwd 123456 >/dev/null ) || rc=1
  rm -rf "$w"
  [ "$rc" -eq 0 ] && [ -s "$out" ] || die "signing failed for $(basename "$out")"
}

OK_COUNT=0
: > "$SHASUMS.new"

process_app() {
  local idx="$1" name apl
  name="$(jq -r ".apps[$idx].name" "$DESC")"
  want_app "$name" || { log "skip $name"; return 0; }
  apl="$(jq -r ".apps[$idx].apl // \"normal\"" "$DESC")"

  prepare_clone "$idx"
  log "=== $name ($(jq -r ".apps[$idx].git" "$DESC") @ $(git -C "$SRCDIR" rev-parse --short HEAD)) ==="
  build_hvigor_app "$SRCDIR"

  local nmod m; nmod="$(jq -r ".apps[$idx].modules | length" "$DESC")"
  for (( m=0; m<nmod; m++ )); do
    local srcPath output dest install_dir unsigned_name unsigned bundle
    srcPath="$(jq -r ".apps[$idx].modules[$m].srcPath" "$DESC")"
    output="$(jq -r ".apps[$idx].modules[$m].output" "$DESC")"
    dest="$(jq -r ".apps[$idx].modules[$m].dest" "$DESC")"
    install_dir="$(jq -r ".apps[$idx].modules[$m].install_dir" "$DESC")"
    unsigned_name="${output/-signed.hap/-unsigned.hap}"
    unsigned="${SRCDIR}/${srcPath}/build/default/outputs/default/${unsigned_name}"
    [ -f "$unsigned" ] || die "$name: expected build output missing: $unsigned"
    bundle="${install_dir##*/}"
    sign_hap "$unsigned" "${OUT_DIR}/${dest}" "$bundle" "$apl"
    ( cd "$OUT_DIR" && sha256sum "$dest" >> "$SHASUMS.new" )
    log "  + ${dest}  <- ${unsigned_name} (signed apl=${apl})"
    OK_COUNT=$((OK_COUNT+1))
  done
}

# --- main --------------------------------------------------------------------
[ -f "$DESC" ] || die "descriptor not found: $DESC"
mkdir -p "$OUT_DIR"

NAPPS="$(jq -r '.apps | length' "$DESC")"
for (( i=0; i<NAPPS; i++ )); do process_app "$i"; done

[ "$OK_COUNT" -gt 0 ] || die "no HAPs were produced"
mv -f "$SHASUMS.new" "$SHASUMS"

log "Done: ${OK_COUNT} HAP(s) in ${OUT_DIR#$ROOT/}"
log "Provenance: vendor/oniro/oniro-haps/oniro-haps.json   Checksums: ${SHASUMS#$ROOT/}"
