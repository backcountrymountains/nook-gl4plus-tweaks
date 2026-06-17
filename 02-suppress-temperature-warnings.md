# Tweak 02 — Suppress Temperature Warning Dialogs

**Requires:** Root + Magisk

## The problem

The Nook shows a modal temperature warning dialog at 48°C. On the GL4 Plus this
threshold is conservative enough to trigger in a warm room or during extended
reading sessions, interrupting what you're doing with a dialog you have to dismiss.

There are two independent warning implementations on this device — one in
`com.nook.partner` and one in the system UI — so both need to be suppressed.

## The fix

Applied on every boot:

1. **Disable `StatusBarService`** — removes the `com.nook.partner` warning layer.
2. **Set `show_temperature_warning = 0`** — suppresses the SystemUI warning layer.

Disabling `StatusBarService` does **not** affect `GlowLightService` (warmth
control) — they are separate services within the same package and warmth continues
to work after this change.

The Android framework's own thermal protection (hardware shutdown at 50°C) remains
fully active. This tweak only removes the early-warning dialogs.

## Install via Magisk app (recommended)

1. Transfer `files/nook-gl4plus-suppress-temp-v1.zip` to the device.
2. Open the **Magisk** app on the device.
3. Tap **Modules** → **Install from storage**.
4. Select `nook-gl4plus-suppress-temp-v1.zip`.
5. Reboot when prompted.

The module's `service.sh` runs as root after every boot and re-applies all three
steps, so they survive factory resets and reboots.

To uninstall: disable or remove the module in the Magisk app and reboot. The
`pm disable` change to `StatusBarService` persists in the package database — if
you want to fully restore temperature warnings after removing the module, also run
the `pm enable` command in the manual section below.

## Verify

```sh
adb shell dumpsys package com.nook.partner | grep -A 10 disabledComponents
# Should include: com.nook.partner.statusbar.StatusBarService

adb shell settings get global show_temperature_warning
# Should output: 0
```

> **Tested:** Verified on bnrv1300 (Android 8.1, Magisk 24.2) — 2026-06-17.
> All checks above confirmed post-reboot via `scripts/verify_modules.sh`.
>
> Note: `service.sh` sets `show_temperature_warning` in a background subshell
> that polls until the Settings provider is ready. On this device the provider
> is not reliably available at Magisk's late-start service time, so the value
> is written a few seconds after the boot animation finishes rather than
> immediately at boot.

## Safety note

| Protection layer | Status after this tweak |
|---|---|
| `com.nook.partner` warning dialog (48°C / 8°C) | Removed |
| SystemUI custom warning dialog | Removed |
| Android `BatteryService` thermal shutdown | **Still active** |
| Kernel thermal governor / hardware OCP | **Still active** |

---

## Manual install via ADB (advanced / for reference)

These steps are preserved for reference if you need to apply the changes without
the Magisk app, or want to understand exactly what the module does.

```sh
adb shell su -c 'pm disable com.nook.partner/.statusbar.StatusBarService'
adb shell su -c 'am force-stop com.nook.partner'
adb shell settings put global show_temperature_warning 0
```

### To undo (ADB)

```sh
adb shell su -c 'pm enable com.nook.partner/.statusbar.StatusBarService'
adb shell settings put global show_temperature_warning 1
```
