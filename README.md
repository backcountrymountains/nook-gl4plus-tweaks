# Nook Glowlight 4 Plus — Tweaks

A collection of fixes for common annoyances on the **Nook Glowlight 4 Plus**
(model `bnrv1300`, Android 8.1). Each tweak is independent — apply as many or
as few as you want.

---

## Device

| Field | Value |
|---|---|
| Model | Nook Glowlight 4 Plus |
| Internal ID | `bnrv1300` |
| Android | 8.1 (Oreo) |

## Prerequisites

Most tweaks require **root access** and **ADB**. If you don't have these yet:

- **Root:** Install [Magisk](https://github.com/topjohnwu/Magisk). This requires
  unlocking the bootloader, which will factory-reset the device.
- **ADB:** Enable USB debugging in Settings → Developer Options. Connect via USB
  or WiFi. All commands below assume a working `adb` connection.

The deep-sleep tweak also requires [KOReader](https://github.com/backcountrymountains/koreader-nook-gl4plus)
to be installed.

---

## Tweaks

| # | Tweak | Requires | What it fixes |
|---|---|---|---|
| [01](01-block-ota-updates.md) | Block OTA firmware updates | Root | Prevents B&N from pushing updates that undo your customizations |
| [02](02-suppress-temperature-warnings.md) | Suppress temperature warnings | Root | Eliminates false-positive temperature dialogs in warm environments |
| [03](03-deep-sleep-battery.md) | Deep sleep between pages | KOReader + WRITE_SETTINGS | Extends battery life from hours to days while reading |
| [04](04-sleep-cover.md) | Sleep cover from KOReader | Root + Magisk | Shows your current book cover on the sleep screen instead of stock B&N art |

---

## Files included

```
files/
  patches/
    2111-nook-gl4plus-deepsleep.lua   ← deep sleep KOReader patch (tweak 03)
  sleep_cover/
    module.prop                        ← Magisk module files (tweak 04)
    service.sh
    cover_watcher.sh
    cover_handler.sh
```

---

## Technical reference

For the full reverse-engineering notes behind these tweaks, see
[nook-gl4plus-research](https://github.com/backcountrymountains/nook-gl4plus-research).
