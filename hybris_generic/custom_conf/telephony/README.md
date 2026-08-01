# Carrier APN database

`pdp_profile.json` here replaces the one OHOS ships at
`/system/etc/telephony/pdp_profile.json`, which covers MCC 460 only.

## Why a whole database

`CellularDataRdbHelper::QueryApns` looks a SIM up by exact MCC+MNC —
`predicates.EqualTo(PdpProfileData::MCCMNC, mcc + mnc)`. There is no
wildcard row, no MCC-only fallback, and no compiled-in default. With no
match, `ApnManager::CreateAllApnItemByDatabase` returns zero items and
data silently never starts: the connection state machine reports
`matchedApns is empty` and nothing else in the log says why.

There is also nothing automatic to fall back to. The standards-based
candidate — activate with a blank APN and let the network substitute the
subscription default — was tested on ansuz and rejected by the network
with 3GPP cause 27, `MISSING_UNKNOWN_APN`. The Halium container carries
APN data of its own (`/android/vendor/etc/md/apncfg/`, 504 operators)
but only IMS and initial-attach entries, no internet APN; and
`/android/system` is the Ubuntu Touch rootfs, so Android's own database
was never on the device.

So the table has to be comprehensive, or the image works only on SIMs
somebody thought to add by hand.

## Provenance

Generated from AOSP's carrier database:

* repository `platform/device/sample`, branch `android14-release`
* file `etc/apns-full-conf.xml`
* commit `89b86021ff1ee7977a4e979eb70d5d7cec72a4aa`
* Apache-2.0, `Copyright 2006, The Android Open Source Project`

3430 entries in, 3442 out over 1248 operators. 25 are dropped for having
no `apn` attribute (OHOS's `IsNeedInsertToTable` requires the key), 14
for having no MCC/MNC (they exist for Android's carrier-id matcher,
which OHOS has no equivalent of), and 277 exact duplicates are collapsed
— the `pdp_profile` table carries an implicit UNIQUE index over every
column, so they would be rejected one at a time on import anyway. 328
rows are added: generic fallbacks for the 83 operators whose AOSP rows
are *all* MVNO-qualified, without which OHOS can reach none of them.
See `add_generic_fallbacks()` in the script.

3436 of those 3442 land in the table on a real import; the last handful
differ only in a column the converter's duplicate check compares but the
table's UNIQUE index does not, and the index wins. Harmless, and not
worth chasing — but it is why the two numbers differ if you count rows
on a device.

## Refreshing it

```bash
curl -s "https://android.googlesource.com/device/sample/+/refs/heads/android14-release/etc/apns-full-conf.xml?format=TEXT" \
    | base64 -d > /tmp/apns-full-conf.xml
./convert_apns.py /tmp/apns-full-conf.xml pdp_profile.json
```

The script's header documents the field mapping and the three parser
rules that shape it. Four things worth knowing before editing either:

* **MVNO rows need translating twice over.** AOSP spells the GID
  discriminator `mvno_type="gid"`; OHOS queries for `MvnoType::GID1 ==
  "gid1"` and matches nothing otherwise. And where Android falls back to
  an operator's unqualified rows when no MVNO matches, OHOS's fallback
  query throws away every row that *has* an `mvno_type`
  (`ReadApnResult`), so an operator with nothing but MVNO rows is
  unreachable. Both are handled in the converter; both were found the
  hard way, because the symptom is the usual one — no data, no error.
* **Every field is copied into a `char[256]`** by
  `ApnItem::MakeApn`, and a value that does not fit makes it return
  `nullptr` — silently dropping that APN. The converter refuses to emit
  such a row instead.
* **The JSON is imported into SQLite once**, in
  `RdbPdpProfileCallback::OnCreate`. An existing device ignores a changed
  file; delete
  `/data/app/el1/100/database/com.ohos.telephonydataability/net.db` to
  force a re-import. There is no upgrade path for a device already in the
  field — `OnUpgrade` migrates the schema but never re-reads the file.

## Adding an operator AOSP does not have

Append an entry to `pdp_profile.json` directly and note it here.
Nothing regenerates the file automatically, but a refresh from upstream
would overwrite a hand edit, so keep any local addition listed:

* *(none at present — Iliad Italia 222-50, the carrier this port was
  brought up against, is in the AOSP database as `iliad`, and reaches
  OHOS through the generic fallback described above: its only AOSP row
  is gated on `gid1` `F003`, which the test SIM does not carry.)*
