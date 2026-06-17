# Tweak 01 — Block OTA Firmware Updates

**Requires:** Root + Magisk

## The problem

Barnes & Noble's firmware update service checks for updates every 24 hours, even
while the device is idle. If B&N pushes an update it will be downloaded and applied
automatically — potentially re-enabling components you disabled, overwriting Magisk,
or changing system behaviour in ways that break other tweaks.

## The fix

Two complementary layers applied on every boot:

1. **Disable the OTA components** via `pm disable` so the update service never runs.
2. **Redirect the OTA server URL to localhost** via `/sdcard/ota_server.conf` — a
   device-provided override that keeps updates blocked even if the components are
   ever re-enabled.

## Install via Magisk app (recommended)

1. Transfer `files/nook-gl4plus-block-ota-v1.zip` to the device.
2. Open the **Magisk** app on the device.
3. Tap **Modules** → **Install from storage**.
4. Select `nook-gl4plus-block-ota-v1.zip`.
5. Reboot when prompted.

The module's `service.sh` runs as root after every boot and re-applies both layers,
so they survive factory resets and any accidental `pm enable` calls.

To uninstall: disable or remove the module in the Magisk app and reboot. Note that
`pm disable` changes to package components persist in the package database — if you
want to fully restore OTA functionality after removing the module, also run the
`pm enable` commands in the manual section below.

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

> **Tested:** Verified on bnrv1300 (Android 8.1, Magisk 24.2) — 2026-06-17.
> All checks above confirmed post-reboot via `scripts/verify_modules.sh`.
>
> Note: `service.sh` writes `ota_server.conf` in a background subshell that
> polls until `/sdcard` is mounted. On this device `/sdcard` (FUSE) is not
> available at Magisk's late-start service time (~11s before `boot_complete`),
> so the file appears a few seconds after the boot animation finishes — not
> immediately at boot.

---

## Manual install via ADB (advanced / for reference)

These steps are preserved for reference if you need to apply the changes without
the Magisk app, or want to understand exactly what the module does.

```sh
adb shell su -c 'pm disable com.nook.partner/.otamanager.OtaIntentService'
adb shell su -c 'pm disable com.nook.partner/.otamanager.SideloadInstaller'
adb shell su -c 'pm disable com.nook.partner/.oobe.OobeOtaActivity'
adb shell "echo 'http://127.0.0.1/' > /sdcard/ota_server.conf"
```

> `OtaIntentService$BootCompleteReceiver` cannot be targeted by `pm disable`
> directly. Disabling `OtaIntentService` is sufficient — when the receiver fires
> on boot it attempts to start the disabled service, which Android silently rejects.

### To undo (ADB)

```sh
adb shell su -c 'pm enable com.nook.partner/.otamanager.OtaIntentService'
adb shell su -c 'pm enable com.nook.partner/.otamanager.SideloadInstaller'
adb shell su -c 'pm enable com.nook.partner/.oobe.OobeOtaActivity'
adb shell rm /sdcard/ota_server.conf
```
