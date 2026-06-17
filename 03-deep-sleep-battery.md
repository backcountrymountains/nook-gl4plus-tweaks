# Tweak 03 — Deep Sleep Between Pages (Battery Life)

**Requires:** KOReader installed, "Modify system settings" permission granted to KOReader

## The problem

With a stock KOReader install, the Nook's CPU stays in a normal active state
between page turns. The e-ink screen holds its image without power, but the CPU
and memory subsystem keep drawing current. In practice this means the battery lasts
hours, not days, during a reading session.

## The fix

The GL4 Plus has an AllWinner CPU with a hardware deep-sleep mode controlled by a
`Settings.System` key (`power_enhance_enable`). When set to `1`, the CPU drops to
minimum power between page turns while the screen image is preserved unchanged.

The patch file `2111-nook-gl4plus-deepsleep.lua` (included in `files/patches/`)
automates this cycle: on every page turn it briefly wakes the CPU, renders the
next page, then puts the CPU back to sleep after 1 second. It also handles the
button-wake timing so page-turn buttons work correctly when waking from deep sleep.

> This patch is derived from [nopowen](https://github.com/Codereamp/nopowen) by
> NiLuJe, adapted for the GL4 Plus with first-press button handling and
> rotation-aware page direction.

## Steps

### 1. Grant KOReader "Modify system settings"

The patch writes to `Settings.System`, which requires a one-time permission grant:

```sh
adb shell appops set org.koreader.launcher WRITE_SETTINGS allow
```

This survives KOReader updates but resets on a full uninstall + reinstall.

### 2. Copy the patch file to the device

```sh
adb push files/patches/2111-nook-gl4plus-deepsleep.lua /sdcard/koreader/patches/
```

The `/sdcard/koreader/patches/` directory must exist (KOReader creates it on first
run). KOReader loads all `.lua` files from this directory on startup.

### 3. Restart KOReader

Use KOReader's own **Exit** button (not the home or back button) and reopen it, so
it performs a full restart and loads the patch.

## Verify

Open a book and turn a few pages. In ADB logcat, you should see:

```sh
adb shell logcat -s KOReader:I
# KOReader: KRP: i_am_paging!
# KOReader: KRP: reseting deepsleep (setting power_enhance_enable to 0)
# KOReader: KRP: settings set returned ok
# KOReader: KRP: scheduling DS for seconds: 1
# KOReader: KRP: scheduled event. Setting power_enhance_enable to 1 (going to deep sleep)
# KOReader: KRP: settings set returned ok
```

## Notes

- **AutoWarmth conflict:** KOReader's AutoWarmth plugin can interfere with warmth
  settings when resuming from deep sleep. Disable it in Plugin Manager if your
  warmth level resets unexpectedly.
- **WiFi and deep sleep:** Deep sleep cuts CPU activity but does not turn off WiFi
  by itself. If you want WiFi off while reading (for maximum battery savings),
  toggle it manually before opening a book or use KOReader's WiFi setting.
- **Screen timeout:** The patch keeps the screen on (`FLAG_KEEP_SCREEN_ON`) while
  reading so Android does not interfere with deep sleep. This means the screen will
  not turn off automatically between pages — the power button is the way to sleep
  the device manually.

## Undo

Delete the patch file and restart KOReader:

```sh
adb shell rm /sdcard/koreader/patches/2111-nook-gl4plus-deepsleep.lua
```
