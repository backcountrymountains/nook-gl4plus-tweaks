# Tweak 02 — Suppress Temperature Warning Dialogs

**Requires:** Root

## The problem

The Nook shows a modal "temperature warning" dialog when the battery reaches 48°C.
On the GL4 Plus this threshold is conservative enough that it can trigger in a warm
room or during extended reading sessions, interrupting what you're doing with a
dialog you have to dismiss before you can continue.

There are two independent warning implementations on this device — one in
`com.nook.partner` and one in the system UI — so you need to suppress both.

## The fix

1. Disable `StatusBarService` (the `com.nook.partner` warning layer).
2. Set `show_temperature_warning = 0` (suppresses the SystemUI warning layer).

Disabling `StatusBarService` removes the B&N temperature dialog but does **not**
affect `GlowLightService` (the warmth control service) — warmth continues to work
after this change.

The Android framework's own thermal protection (hardware shutdown at 50°C) remains
fully active regardless. This tweak only removes the early-warning dialogs, not the
final safety shutdowns.

## Steps

```sh
adb shell su -c 'pm disable com.nook.partner/.statusbar.StatusBarService'
adb shell su -c 'am force-stop com.nook.partner'
adb shell settings put global show_temperature_warning 0
```

The `settings put` change persists in the Settings database across reboots. If you
use the `sleep_cover` Magisk module (tweak 04), it also re-applies this setting on
every boot as a safety net in case of factory reset.

## Verify

```sh
adb shell dumpsys package com.nook.partner | grep -A 10 disabledComponents
# Should include: com.nook.partner.statusbar.StatusBarService

adb shell settings get global show_temperature_warning
# Should output: 0
```

## Undo

```sh
adb shell su -c 'pm enable com.nook.partner/.statusbar.StatusBarService'
adb shell settings put global show_temperature_warning 1
```

## Safety note

| Protection layer | Status after this tweak |
|---|---|
| `com.nook.partner` warning dialog (48°C / 8°C) | Removed |
| SystemUI custom warning dialog | Removed |
| Android `BatteryService` thermal shutdown | **Still active** |
| Kernel thermal governor / hardware OCP | **Still active** |

The device will still shut down safely at dangerous temperatures.
