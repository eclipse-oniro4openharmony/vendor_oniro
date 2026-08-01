#!/usr/bin/env python3
# Copyright (c) 2026 Eclipse Oniro for OpenHarmony contributors.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Convert AOSP's apns-full-conf.xml into OHOS's pdp_profile.json.

    ./convert_apns.py apns-full-conf.xml pdp_profile.json

The two files are the same kind of thing — the carrier APN database the
telephony stack looks a SIM's MCC+MNC up in — and the field sets are
almost a bijection, so this is a mechanical translation.  It exists as a
script rather than a one-off because the output is regenerated whenever
the upstream database is refreshed; see README.md for provenance.

Parsing rules on the OHOS side that shape the output
(base/telephony/telephony_data/common/src/parser_util.cpp):

  * every value must be a JSON *string* — ParseString() ignores anything
    that is not cJSON_String, so numbers have to be quoted;
  * an entry with no "apn" key at all is dropped by IsNeedInsertToTable(),
    but an empty "apn" is legal and meaningful (a blank initial-attach
    APN), so the two cases are kept distinct;
  * absent "apn_protocol"/"apn_roam_protocol" default to "IP", which is
    also what Android means by an absent protocol attribute, so those are
    only emitted when present;
  * absent "auth_type" leaves ApnAuthType::INIT, which the parser then
    resolves to NONE or PAP_OR_CHAP depending on whether a user name is
    set — better than forcing a value, so it is also only emitted when
    present.

And one on the consumer side (cellular_data ApnItem::MakeApn): every
field is copied into a char[256] with strcpy_s, and a value that does not
fit makes MakeApn return nullptr, silently dropping the whole APN.  This
script therefore refuses to emit a row that would be truncated rather
than let it disappear at runtime.

MVNO rows need two adjustments, because the two sides disagree about
both the vocabulary and the fallback — see MVNO_TYPES and
add_generic_fallbacks() below.
"""

import json
import sys
import xml.etree.ElementTree as ET

# ApnItem::ALL_APN_ITEM_CHAR_LENGTH, minus the NUL strcpy_s needs.
MAX_FIELD = 255

# AOSP attribute -> OHOS key, for the fields that map straight across.
# Android's authtype numbering (0 none, 1 PAP, 2 CHAP, 3 PAP or CHAP) is
# identical to OHOS's ApnAuthType, and the protocol spellings ("IP",
# "IPV6", "IPV4V6") match too, so neither needs a translation table.
DIRECT = {
    "carrier": "operator_name",
    "mcc": "mcc",
    "mnc": "mnc",
    "apn": "apn",
    "user": "auth_user",
    "password": "auth_pwd",
    "authtype": "auth_type",
    "type": "apn_types",
    "protocol": "apn_protocol",
    "roaming_protocol": "apn_roam_protocol",
    "mmsc": "home_url",
    "mvno_match_data": "mvno_match_data",
    "server": "server",
}

# The MVNO discriminators, AOSP spelling -> OHOS spelling.  Only the
# "gid" one differs, and it differs fatally: cellular_data queries
# MVNO_TYPE with EqualTo against MvnoType::GID1 == "gid1"
# (telephony_data pdp_profile_data.h), so an AOSP "gid" row is matched by
# nothing.  One row in the database spells its type "IMSI", hence the
# lowercasing.  A type OHOS does not know is worse than no type at all —
# see add_generic_fallbacks() — so anything unrecognised is dropped.
MVNO_TYPES = {"spn": "spn", "imsi": "imsi", "gid": "gid1", "iccid": "iccid"}

# Deliberately dropped:
#
#   bearer, network_type_bitmask
#       OHOS's bearing_system_type is its own enumeration (LTE=1, HSPAP=2,
#       …), not the RIL radio-technology numbering Android's `bearer` uses,
#       and nothing in cellular_data filters on it.  Mapping it would mean
#       inventing a correspondence; two entries in the whole database set
#       it.
#   carrier_id, mtu, mtusize, profile_id, max_conns, max_conns_time,
#   modem_cognitive, carrier_enabled, user_visible, user_editable
#       no counterpart in pdp_profile — OHOS carries its own profile ids
#       (the database row), takes the MTU from the data-call result, and
#       has no per-APN connection limits or UI-visibility flags.


def host_port(attrs, host_key, port_key):
    """Android keeps proxy host and port apart; OHOS keeps one "host:port"
    string, which CellularDataStateMachine::SplitProxyIpAddress splits on
    ':' again."""
    host = attrs.get(host_key, "").strip()
    port = attrs.get(port_key, "").strip()
    if not host:
        return ""
    return f"{host}:{port}" if port else host


def convert(entry):
    attrs = entry.attrib
    # No MCC/MNC means QueryApns can never match it — those rows exist for
    # Android's carrier-id matcher, which OHOS does not have.
    if not attrs.get("mcc") or not attrs.get("mnc"):
        return None, "no mcc/mnc"
    if "apn" not in attrs:
        return None, "no apn attribute"

    out = {}
    for src, dst in DIRECT.items():
        if src in attrs:
            out[dst] = attrs[src]

    mvno_type = MVNO_TYPES.get(attrs.get("mvno_type", "").lower())
    if mvno_type and out.get("mvno_match_data"):
        out["mvno_type"] = mvno_type
    else:
        out.pop("mvno_match_data", None)

    proxy = host_port(attrs, "proxy", "port")
    if proxy:
        out["ip_addr"] = proxy
    mms_proxy = host_port(attrs, "mmsproxy", "mmsport")
    if mms_proxy:
        out["mms_ip_addr"] = mms_proxy

    for key, value in out.items():
        if len(value) > MAX_FIELD:
            return None, f"{key} is {len(value)} chars"
    return out, None


def add_generic_fallbacks(entries):
    """Give every operator at least one row the generic query can see.

    OHOS runs two queries.  ApnManager::CreateMvnoApnItems asks for rows
    whose mvno_type matches, and compares mvno_match_data against the
    SIM's SPN/IMSI/GID1/ICCID; if that finds nothing it falls back to
    QueryApns — which reads *every* row for the MCC+MNC and then throws
    away any whose mvno_type is set (CellularDataRdbHelper::
    ReadApnResult: `if (apnBean.mvnoType.empty())`).

    So an operator whose rows are all MVNO-qualified has no reachable APN
    at all unless the SIM happens to match one, and gets no data with no
    error — which is exactly what Iliad Italia (222-50, a single
    `mvno_type="gid"` row) did.  Android does not have this problem: its
    own fallback is the unqualified rows for the same operator, and it
    simply uses them when no MVNO matches.

    Restore that fallback by duplicating the rows of any such operator
    with the MVNO fields stripped.  Operators that already have an
    unqualified row are left alone — their MVNO rows stay
    discriminating, which is the point of them.
    """
    by_operator = {}
    for entry in entries:
        by_operator.setdefault((entry["mcc"], entry["mnc"]), []).append(entry)

    added = 0
    for rows in by_operator.values():
        if any("mvno_type" not in row for row in rows):
            continue
        for row in list(rows):
            generic = {k: v for k, v in row.items()
                       if k not in ("mvno_type", "mvno_match_data")}
            entries.append(generic)
            added += 1
    return added


def main(argv):
    if len(argv) != 3:
        sys.exit(f"usage: {argv[0]} <apns-full-conf.xml> <pdp_profile.json>")

    root = ET.parse(argv[1]).getroot()
    entries, skipped = [], {}
    for entry in root:
        if entry.tag != "apn":
            continue
        converted, why = convert(entry)
        if converted is None:
            skipped[why] = skipped.get(why, 0) + 1
            continue
        entries.append(converted)

    fallbacks = add_generic_fallbacks(entries)

    # The pdp_profile table carries an implicit UNIQUE index over every
    # column, so exact duplicates — AOSP lists a fair number, and
    # add_generic_fallbacks() can produce more — would be rejected one by
    # one at import.  Dropping them here keeps the file smaller and the
    # row count in the database predictable.
    unique, seen = [], set()
    for entry in entries:
        key = json.dumps(entry, sort_keys=True)
        if key not in seen:
            seen.add(key)
            unique.append(entry)
    duplicates = len(entries) - len(unique)
    entries = unique

    with open(argv[2], "w", encoding="utf-8") as out:
        json.dump({"version": 1, "operator_infos": entries}, out,
                  indent=4, ensure_ascii=False)
        out.write("\n")

    print(f"{len(entries)} entries written to {argv[2]}")
    print(f"  of which {fallbacks} are generic fallbacks for "
          f"MVNO-only operators")
    print(f"  dropped {duplicates} exact duplicates")
    for why, count in sorted(skipped.items()):
        print(f"  skipped {count}: {why}")


if __name__ == "__main__":
    main(sys.argv)
