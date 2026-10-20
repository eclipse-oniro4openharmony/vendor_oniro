/*
 * Copyright (c) 2026 Eclipse Oniro for OpenHarmony contributors.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * location_timezone — set the system time zone from the device's location.
 *
 * Settings' Date & time page promises "Location services needs to be enabled
 * to automatically set the time zone", but nothing in OpenHarmony does it:
 * the only automatic writer of the time zone is telephony's NITZ handler,
 * which needs a SIM on a network (HarmonyOS fills the gap with closed
 * vendor code). Everything this needs is in the image, though: the location
 * framework, and i18n's offline zone-boundary map behind
 * I18nTimeZone::GetTimezoneIdByLocation (/system/usr/ohos_timezone).
 *
 * Policy:
 *  - Acts only when "Set automatically" is on (persist.time.auto_time, the
 *    param Settings' single toggle drives together with the settingsdata
 *    auto_time/auto_timezone keys) and the location switch is on.
 *  - Prefers the framework's last known location, which any app's fix
 *    refreshes for free. Only when that is older than FRESH_FIX_MS does it
 *    ask for one fix of its own, and at most once per ACTIVE_MIN_GAP_MS.
 *  - Runs on start, on a network change (the usual sign of travel), when
 *    either switch is turned on, and every PERIODIC_MS (cached location
 *    only, so the periodic check never powers up GNSS).
 *  - Leaves the zone alone when the current one is among the zones at the
 *    fix: near a border the map can name several, and NITZ may already have
 *    picked the right one.
 */

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "common_event_manager.h"
#include "common_event_subscriber.h"
#include "common_event_support.h"
#include "hilog/log.h"
#include "i18n_timezone.h"
#include "ipc_skeleton.h"
#include "iremote_stub.h"
#include "i_locator_callback.h"
#include "location.h"
#include "locator_impl.h"
#include "matching_skills.h"
#include "parameter.h"
#include "request_config.h"
#include "time_service_client.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0xD002563
#define LOG_TAG "LocationTimezone"

#define LTZ_LOGI(fmt, ...) HILOG_INFO(LOG_CORE, "%{public}s: " fmt, __func__, ##__VA_ARGS__)
#define LTZ_LOGW(fmt, ...) HILOG_WARN(LOG_CORE, "%{public}s: " fmt, __func__, ##__VA_ARGS__)
#define LTZ_LOGE(fmt, ...) HILOG_ERROR(LOG_CORE, "%{public}s: " fmt, __func__, ##__VA_ARGS__)

namespace OHOS {
namespace Oniro {
namespace {

namespace Loc = ::OHOS::Location;

constexpr const char *AUTO_TIME_PARAM = "persist.time.auto_time";
constexpr const char *LOCATION_SWITCH_PARAM = "persist.location.switch_mode";

constexpr int64_t FRESH_FIX_MS = 30 * 60 * 1000;        /* a cached fix this recent is used as is */
constexpr int64_t ACTIVE_MIN_GAP_MS = 30 * 60 * 1000;   /* at most one fix of our own per 30 min */
constexpr int32_t ACTIVE_TIMEOUT_MS = 90 * 1000;        /* a cold GNSS start can take this long */
constexpr int64_t PERIODIC_MS = 60 * 60 * 1000;
constexpr int64_t START_DELAY_MS = 60 * 1000;           /* let boot settle before the first check */
constexpr int64_t NETWORK_DEBOUNCE_MS = 30 * 1000;      /* connectivity events come in bursts */

enum class Reason { START, NETWORK, SWITCH_ON, PERIODIC };

const char *ReasonName(Reason r)
{
    switch (r) {
        case Reason::START: return "start";
        case Reason::NETWORK: return "network change";
        case Reason::SWITCH_ON: return "switch on";
        default: return "periodic";
    }
}

int64_t NowMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
}

int64_t MonoMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

std::string GetParam(const char *key)
{
    char value[256] = { 0 };
    if (GetParameter(key, "", value, sizeof(value)) <= 0) {
        return "";
    }
    return value;
}

bool AutoTimeOn()
{
    /* Settings' default when unset is ON, as is time.para's. */
    std::string v = GetParam(AUTO_TIME_PARAM);
    return v.empty() || v == "ON";
}

/* persist.location.switch_mode is per user, e.g. {"100":1}. A cheap
 * any-user-has-it-on test that saves a locator round trip (which would
 * start the on-demand locationhub) while everything is off; the locator's
 * own answer is authoritative. */
bool LocationSwitchMaybeOn()
{
    return GetParam(LOCATION_SWITCH_PARAM).find(":1") != std::string::npos;
}

class Daemon;

class FixCallback : public IRemoteStub<Loc::ILocatorCallback> {
public:
    int OnRemoteRequest(uint32_t code, MessageParcel &data, MessageParcel &reply,
                        MessageOption &option) override
    {
        if (data.ReadInterfaceToken() != GetDescriptor()) {
            return -1;
        }
        if (code == RECEIVE_LOCATION_INFO_EVENT || code == RECEIVE_LOCATION_INFO_EVENT_V9) {
            std::unique_ptr<Loc::Location> loc = Loc::Location::UnmarshallingMakeUnique(data);
            OnLocationReport(loc);
            return 0;
        }
        return IPCObjectStub::OnRemoteRequest(code, data, reply, option);
    }

    void OnLocationReport(const std::unique_ptr<Loc::Location> &location) override
    {
        if (location == nullptr) {
            return;
        }
        std::lock_guard<std::mutex> guard(lock_);
        if (!have_) {
            lat_ = location->GetLatitude();
            lon_ = location->GetLongitude();
            have_ = true;
            cv_.notify_all();
        }
    }

    void OnLocatingStatusChange(const int status) override {}
    void OnErrorReport(const int errorCode) override
    {
        LTZ_LOGW("locator error %{public}d", errorCode);
    }

    bool Wait(int32_t timeoutMs, double &lat, double &lon)
    {
        std::unique_lock<std::mutex> guard(lock_);
        cv_.wait_for(guard, std::chrono::milliseconds(timeoutMs), [this]() { return have_; });
        lat = lat_;
        lon = lon_;
        return have_;
    }

private:
    std::mutex lock_;
    std::condition_variable cv_;
    bool have_ = false;
    double lat_ = 0;
    double lon_ = 0;
};

class Daemon {
public:
    static Daemon &Get()
    {
        static Daemon *daemon = new Daemon();
        return *daemon;
    }

    void Post(Reason reason, int64_t delayMs = 0)
    {
        std::lock_guard<std::mutex> guard(lock_);
        int64_t due = MonoMs() + delayMs;
        /* Coalesce: keep the earliest due time and the most demanding reason
         * (anything but PERIODIC may ask for a fix of our own). */
        if (!pending_ || due < pendingDue_) {
            pendingDue_ = due;
        }
        if (!pending_ || pendingReason_ == Reason::PERIODIC) {
            pendingReason_ = reason;
        }
        pending_ = true;
        cv_.notify_all();
    }

    void Run()
    {
        int64_t nextPeriodic = MonoMs() + PERIODIC_MS;
        for (;;) {
            Reason reason;
            {
                std::unique_lock<std::mutex> guard(lock_);
                for (;;) {
                    int64_t now = MonoMs();
                    if (pending_ && now >= pendingDue_) {
                        break;
                    }
                    if (!pending_ && now >= nextPeriodic) {
                        pending_ = true;
                        pendingReason_ = Reason::PERIODIC;
                        pendingDue_ = now;
                        break;
                    }
                    int64_t wake = pending_ ? std::min(pendingDue_, nextPeriodic) : nextPeriodic;
                    cv_.wait_for(guard, std::chrono::milliseconds(wake - now));
                }
                reason = pendingReason_;
                pending_ = false;
            }
            nextPeriodic = MonoMs() + PERIODIC_MS;
            Evaluate(reason);
        }
    }

private:
    Daemon() = default;

    void Evaluate(Reason reason)
    {
        if (!AutoTimeOn() || !LocationSwitchMaybeOn()) {
            LTZ_LOGI("%{public}s: skipped (auto time %{public}s, location switch %{public}s)",
                     ReasonName(reason), GetParam(AUTO_TIME_PARAM).c_str(),
                     GetParam(LOCATION_SWITCH_PARAM).c_str());
            return;
        }
        auto locator = Loc::LocatorImpl::GetInstance();
        if (locator == nullptr) {
            return;
        }
        bool enabled = false;
        if (locator->IsLocationEnabledV9(enabled) != Loc::ERRCODE_SUCCESS || !enabled) {
            LTZ_LOGI("%{public}s: skipped (locator reports location off)", ReasonName(reason));
            return;
        }

        std::unique_ptr<Loc::Location> cached;
        (void)locator->GetCachedLocationV9(cached);
        int64_t ageS = cached != nullptr ? (NowMs() - cached->GetTimeStamp()) / 1000 : -1;
        LTZ_LOGI("%{public}s: last known fix %{public}s", ReasonName(reason),
                 cached != nullptr ? (std::to_string(ageS) + " s old").c_str() : "none");
        if (cached != nullptr && NowMs() - cached->GetTimeStamp() <= FRESH_FIX_MS) {
            Apply(cached->GetLatitude(), cached->GetLongitude(), "cached fix");
            return;
        }
        if (reason == Reason::PERIODIC) {
            return;
        }
        if (lastActiveMs_ != 0 && MonoMs() - lastActiveMs_ < ACTIVE_MIN_GAP_MS) {
            LTZ_LOGI("%{public}s: no fresh fix, own request rate-limited", ReasonName(reason));
            return;
        }
        lastActiveMs_ = MonoMs();

        double lat = 0;
        double lon = 0;
        if (RequestFix(*locator, lat, lon)) {
            Apply(lat, lon, ReasonName(reason));
        } else {
            LTZ_LOGI("%{public}s: no fix within %{public}d s", ReasonName(reason), ACTIVE_TIMEOUT_MS / 1000);
        }
    }

    bool RequestFix(Loc::LocatorImpl &locator, double &lat, double &lon)
    {
        /* One fix, fastest available source. The zone map's resolution is
         * kilometres, so accuracy hardly matters. */
        auto config = std::make_unique<Loc::RequestConfig>();
        config->SetScenario(Loc::SCENE_UNSET);
        config->SetPriority(Loc::PRIORITY_FAST_FIRST_FIX);
        config->SetFixNumber(1);
        config->SetTimeInterval(1);
        config->SetTimeOut(ACTIVE_TIMEOUT_MS);
        sptr<FixCallback> host = new (std::nothrow) FixCallback();
        if (host == nullptr) {
            return false;
        }
        sptr<Loc::ILocatorCallback> callback = host;
        Loc::LocationErrCode err = locator.StartLocatingV9(config, callback);
        if (err != Loc::ERRCODE_SUCCESS) {
            LTZ_LOGW("StartLocating failed: %{public}d", err);
            return false;
        }
        bool got = host->Wait(ACTIVE_TIMEOUT_MS, lat, lon);
        (void)locator.StopLocatingV9(callback);
        return got;
    }

    void Apply(double lat, double lon, const char *source)
    {
        /* x is longitude, y latitude (CheckLatitudeAndLongitude). */
        std::vector<std::string> zones = Global::I18n::I18nTimeZone::GetTimezoneIdByLocation(lon, lat);
        if (zones.empty()) {
            LTZ_LOGW("no zone at the %{public}s (open sea, or no map data)", source);
            return;
        }
        auto client = MiscServices::TimeServiceClient::GetInstance();
        std::string current = client->GetTimeZone();
        for (const auto &zone : zones) {
            if (zone == current) {
                return;
            }
        }
        if (client->SetTimeZone(zones[0])) {
            LTZ_LOGI("time zone %{public}s -> %{public}s (from %{public}s)", current.c_str(),
                     zones[0].c_str(), source);
        } else {
            LTZ_LOGE("SetTimeZone(%{public}s) refused", zones[0].c_str());
        }
    }

    std::mutex lock_;
    std::condition_variable cv_;
    bool pending_ = false;
    Reason pendingReason_ = Reason::PERIODIC;
    int64_t pendingDue_ = 0;
    int64_t lastActiveMs_ = 0;
};

class NetworkSubscriber : public EventFwk::CommonEventSubscriber {
public:
    explicit NetworkSubscriber(const EventFwk::CommonEventSubscribeInfo &info)
        : EventFwk::CommonEventSubscriber(info) {}

    void OnReceiveEvent(const EventFwk::CommonEventData &data) override
    {
        Daemon::Get().Post(Reason::NETWORK, NETWORK_DEBOUNCE_MS);
    }
};

/* Last seen state of each switch, so only an off -> on transition counts.
 * WatchParameter also calls back once at registration with the current
 * value; seeded from the same value first, that call is a no-op and the
 * delayed START check stays the first one. */
std::mutex g_switchLock;
bool g_autoTimeWasOn = false;
bool g_locationWasOn = false;

void OnSwitchChanged(const char *key, const char *value, void *context)
{
    (void)context;
    if (key == nullptr || value == nullptr) {
        return;
    }
    bool isAutoTime = strcmp(key, AUTO_TIME_PARAM) == 0;
    bool on = isAutoTime ? (strcmp(value, "ON") == 0) : (strstr(value, ":1") != nullptr);
    bool turnedOn;
    {
        std::lock_guard<std::mutex> guard(g_switchLock);
        bool &was = isAutoTime ? g_autoTimeWasOn : g_locationWasOn;
        turnedOn = on && !was;
        was = on;
    }
    if (turnedOn) {
        Daemon::Get().Post(Reason::SWITCH_ON);
    }
}

void SubscribeNetwork()
{
    EventFwk::MatchingSkills skills;
    skills.AddEvent(EventFwk::CommonEventSupport::COMMON_EVENT_CONNECTIVITY_CHANGE);
    EventFwk::CommonEventSubscribeInfo info(skills);
    static std::shared_ptr<NetworkSubscriber> subscriber = std::make_shared<NetworkSubscriber>(info);
    /* The event service may not be up yet when init starts us. */
    for (int attempt = 0; attempt < 60; attempt++) {
        if (EventFwk::CommonEventManager::SubscribeCommonEvent(subscriber)) {
            return;
        }
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
    LTZ_LOGE("could not subscribe to connectivity changes");
}

} // namespace
} // namespace Oniro
} // namespace OHOS

int main()
{
    using namespace OHOS::Oniro;
    LTZ_LOGI("started");
    {
        std::lock_guard<std::mutex> guard(g_switchLock);
        g_autoTimeWasOn = AutoTimeOn();
        g_locationWasOn = LocationSwitchMaybeOn();
    }
    if (WatchParameter(AUTO_TIME_PARAM, OnSwitchChanged, nullptr) != 0 ||
        WatchParameter(LOCATION_SWITCH_PARAM, OnSwitchChanged, nullptr) != 0) {
        LTZ_LOGW("could not watch the switch parameters");
    }
    Daemon::Get().Post(Reason::START, START_DELAY_MS);
    std::thread(&Daemon::Run, &Daemon::Get()).detach();
    std::thread(SubscribeNetwork).detach();

    /* Serve the IPC threads that deliver locator callbacks and events. */
    OHOS::IPCSkeleton::JoinWorkThread();
    return 0;
}
