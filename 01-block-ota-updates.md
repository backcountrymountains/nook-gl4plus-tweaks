# Tweak 01 — Block OTA Firmware Updates

**Requires:** Root

## The problem

Barnes & Noble's firmware update service (`OtaIntentService`) checks for updates
every 24 hours, even while the device is idle. If B&N pushes an update, it will
be downloaded and applied automatically — potentially re-enabling components you
disabled, overwriting Magisk, or changing system behaviour in ways that break
other tweaks.

## The fix

Two complementary layers:

1. **Disable the OTA components** via `pm disable` so the update service never runs.
2. **Redirect the OTA server URL to localhost** using a device-provided override
   file — a fallback that keeps updates blocked even if the components are ever
   re-enabled.

## Steps

### Layer 1 — Disable OTA components

```sh
adb shell su -c 'pm disable com.nook.partner/.otamanager.OtaIntentService'
adb shell su -c 'pm disable com.nook.partner/.otamanager.SideloadInstaller'
adb shell su -c 'pm disable com.nook.partner/.oobe.OobeOtaActivity'
```

> The boot receiver (`OtaIntentService$BootCompleteReceiver`) cannot be targeted
> by `pm disable` directly. Disabling `OtaIntentService` is sufficient — when
> the receiver fires on boot it attempts to start the disabled service, which
> Android silently rejects.

### Layer 2 — Redirect the OTA server

```sh
adb shell "echo 'http://127.0.0.1/' > /sdcard/ota_server.conf"
```

`com.nook.partner` reads this file on startup and uses it as the update server URL
instead of the real B&N endpoint. Redirecting to localhost means any update check
that does run will fail gracefully with a connection refused.

## Verify

```sh
adb shell dumpsys package com.nook.partner | grep -A 10 disabledComponents
# Should include:
#   com.nook.partner.otamanager.OtaIntentService
#   com.nook.partner.otamanager.SideloadInstaller
#   com.nook.partner.oobe.OobeOtaActivity

adb shell cat /sdcard/ota_server.conf
# Should output: http://127.0.0.1/
```

## Undo

```sh
adb shell su -c 'pm enable com.nook.partner/.otamanager.OtaIntentService'
adb shell su -c 'pm enable com.nook.partner/.otamanager.SideloadInstaller'
adb shell su -c 'pm enable com.nook.partner/.oobe.OobeOtaActivity'
adb shell rm /sdcard/ota_server.conf
```
