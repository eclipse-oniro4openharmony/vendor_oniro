# location_timezone — automatic time zone from location

Settings → Date & time says *"Location services needs to be enabled to
automatically set the time zone"*, but on OpenHarmony nothing does it. That
hint is a static menu item (`DateAndTimePage.ets` always adds a
`DateZoneMenu`). Only two things ever change the system time zone:

* telephony's NITZ / network-country path (`nitz_update.cpp`), which needs a
  SIM on a network;
* the manual picker in Settings.

HarmonyOS fills the gap with closed vendor code: the empty
`libtelephony_ext_service.z.so` hook in core_service, and network location
from HMS.

All the parts are in the OpenHarmony image already: the location framework,
and i18n's offline zone-boundary map
(`I18nTimeZone::GetTimezoneIdByLocation`, data in `/system/usr/ohos_timezone`).
This daemon connects them.

## Behaviour

| | |
|---|---|
| **Switch** | Acts only while "Set automatically" is on (`persist.time.auto_time`, the param Settings' single toggle writes together with the settingsdata `auto_time` / `auto_timezone` keys) **and** location is on. |
| **Triggers** | 60 s after start; a network change (`COMMON_EVENT_CONNECTIVITY_CHANGE`, debounced 30 s, the usual sign of travel); either switch turning on; every hour. |
| **Source** | The locator's last known fix, which any app's location use refreshes for free, if it is at most 30 min old. Otherwise one fix of its own (fastest-first-fix priority, 90 s timeout), at most once per 30 min and never for the hourly check. So the hourly check never powers up GNSS. |
| **Decision** | Looks the fix up in the zone map. If the current zone is one of the zones found there, nothing changes: near a border the map names several, and NITZ may already have chosen. Otherwise the first zone is set through `TimeServiceClient::SetTimeZone`. |

Cost: one resident process, about 4 MB PSS. Its native token carries
`SET_TIME_ZONE` (apl `system_basic`), the location permissions and
`GET_NETWORK_INFO`, all from `location_timezone.cfg`.

## Integration

Product-independent. A product pulls it in by listing
`//vendor/oniro/location_timezone:location_timezone_group` in its
`bundle.json` `sub_component`, as it does for `wallpaper` and `oniro-haps`,
and by declaring the parts it uses in `deps.components`. hybris_generic does
both.

## Checking it

```bash
hdc shell "hilog -x | grep LocationTimezone"
```

Each evaluation logs one line with its reason and the age of the last known
fix, then either the change (`time zone Asia/Shanghai -> Europe/Rome (from
cached fix)`) or why it did nothing. To force an evaluation, switch "Set
automatically" off and on, or toggle location.

## Limits

* Where no app uses location, the zone follows travel only through the
  daemon's own fixes, which a network change triggers. Those need a GNSS fix
  within 90 s; a phone kept indoors may not get one.
* With location off, nothing happens. That is what the Settings hint says.
* Open sea and data-less areas return no zone; the current one is kept.
