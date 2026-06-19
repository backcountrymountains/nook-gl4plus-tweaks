# Tweak 02 — Suppress Temperature Warning Dialogs

> **DEPRECATED — not recommended. The Magisk zip has been removed from this repo.**
>
> See below for why.

## Why we're not recommending this

The 48°C warning dialog exists for a good reason. It gives you a 2°C window before Android's `BatteryService` shuts the device down at 50°C. Without the dialog, the device just shuts off — no warning, no chance to save your place.

More importantly: **this is an Android platform safety feature, not Nook UI cruft.** The `show_temperature_warning` global setting was put there deliberately by the Android team. Suppressing it means defeating a system-level thermal safeguard, not dismissing an annoying brand overlay.

The original motivation was that the dialog triggers during extended reading sessions or in warm rooms. But 48°C is a genuinely hot device — hot enough that the battery is operating at the top of its safe range. The warning is correct.

E-readers also have a specific risk that phones don't: people leave them face-down, in bags, on car seats, or in direct sunlight without holding them. A phone user feels the heat in their hand. An e-reader reader may not notice until it shuts off.

## What was investigated (for reference)

The GL4 Plus has two independent warning implementations:
- `com.nook.partner`'s `StatusBarService` — warning dialog at 48°C, soft shutdown at 50°C
- Android `SystemUI` — controlled by the `show_temperature_warning` global setting

Both need to be suppressed to eliminate the dialog. The original tweak disabled `StatusBarService` and set `show_temperature_warning = 0`.

Android's `BatteryService` shutdown at 50°C operates independently of both layers and **cannot** be disabled without modifying the framework. It remained active after the tweak (confirmed via live shutdown test). Kernel thermal protections (CPU/GPU throttle at 65°C, hard shutdown at 110°C) are also unaffected.

In summary: the tweak worked as described, but the remaining "protection" — a hard shutdown with no warning — is not an acceptable substitute for the warning dialog it removes.

## If you still want to apply it manually

The steps are preserved here for reference only. We don't recommend using them.

```sh
adb shell su -c 'pm disable com.nook.partner/.statusbar.StatusBarService'
adb shell su -c 'am force-stop com.nook.partner'
adb shell settings put global show_temperature_warning 0
```

### To undo

```sh
adb shell su -c 'pm enable com.nook.partner/.statusbar.StatusBarService'
adb shell settings put global show_temperature_warning 1
```
