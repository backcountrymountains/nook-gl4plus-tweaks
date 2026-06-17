# Tweak 03 — Deep Sleep Between Pages (Battery Life)

**Requires:** Root + KOReader + "Modify system settings" permission granted to KOReader

## The problem

With a stock KOReader install, the Nook's CPU stays active between page turns.
The e-ink screen holds its image without power, but the CPU and memory subsystem
keep drawing current. In practice the battery lasts hours, not days.

## The fix

The GL4 Plus has an AllWinner CPU with a hardware deep-sleep mode controlled by a
`Settings.System` key (`power_enhance_enable`). When set to `1`, the CPU drops to
minimum power between page turns while the screen image is preserved. The patch
automates this cycle on every page turn.

## Why root is required

Root is needed to modify `/system/usr/keylayout/Generic.kl`.

The Nook's four physical page-turn buttons (two on each edge) are mapped in the
factory firmware to scan codes F9–F12. **These are not Android wake keys.** When
the deep-sleep patch puts the device into AllWinner deep sleep
(`power_enhance_enable=1`), Android's `PhoneWindowManager` sets
`mWakefulness=Asleep` and silently drops any button event whose keycode is not in
its hardcoded wake-key list. F9–F12 are not on that list, so button presses do
nothing — the device is stuck asleep.

The fix is to remap the buttons to `BACK` (scan codes 191/192) and `MENU`
(193/194), which **are** hardcoded wake keys in `PhoneWindowManager`. Once
remapped, a button press wakes the device and the patch detects which button was
pressed to determine the page direction.

`/system` is a read-only partition by default. Root is required to remount it
read-write, write the new keymap, and remount it read-only again.

## Steps

### Step 1 — Remap buttons in Generic.kl (requires root)

The script `files/patches/install_generic_kl.sh` handles this. It backs up the
original file on the device before making any changes.

```sh
bash files/patches/install_generic_kl.sh
```

Then reboot for the keymap change to take effect:

```sh
adb reboot
```

To restore the original keymap at any time:

```sh
bash files/patches/install_generic_kl.sh --restore
adb reboot
```

`files/patches/Generic.kl.vendor-section` documents the factory button layout and
the patched layout side-by-side for reference.

### Step 2 — Grant KOReader "Modify system settings"

The patch writes to `Settings.System`, which requires a one-time permission grant:

```sh
adb shell appops set org.koreader.launcher WRITE_SETTINGS allow
```

This survives KOReader updates but resets on a full uninstall + reinstall.

### Step 3 — Copy the patch file to the device

```sh
adb push files/patches/2111-nook-gl4plus-deepsleep.lua /sdcard/koreader/patches/
```

The `/sdcard/koreader/patches/` directory must already exist (KOReader creates it
on first run). KOReader loads all `.lua` files from this directory on startup.

### Step 4 — Restart KOReader

Use KOReader's own **Exit** button (not the home or back button) and reopen it so
it performs a full restart and loads the patch.

## Verify

Open a book and turn a few pages. In ADB logcat you should see:

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
- **WiFi and deep sleep:** Deep sleep reduces CPU activity but does not turn off
  WiFi by itself. Toggle it manually or via KOReader's WiFi setting before reading
  for maximum battery savings.
- **Screen timeout:** The patch holds `FLAG_KEEP_SCREEN_ON` while reading so
  Android does not interfere with deep sleep. The screen will not auto-off between
  pages — use the power button to sleep the device manually.

## Undo

Restore the original keymap (Step 1 above), then delete the patch:

```sh
bash files/patches/install_generic_kl.sh --restore
adb reboot
adb shell rm /sdcard/koreader/patches/2111-nook-gl4plus-deepsleep.lua
```
