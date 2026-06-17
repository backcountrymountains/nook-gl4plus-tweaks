# Tweak 04 — Sleep Cover from KOReader

**Requires:** Root + Magisk

## The problem

When the Nook's screen goes to sleep it shows one of six stock B&N artwork images
(chosen at random). There is no built-in way to replace these with your own image.

## The fix

KOReader writes the current book's cover image to
`/sdcard/koreader/sleep_cover.png` every time you open a book. The `sleep_cover`
Magisk module watches for this file to change and copies it to all six art slots in
`/system/media/SleepImageNook/`. When the Nook's sleep screen service reads the art
files on the next screen-off, it shows your book cover.

The watcher is event-driven (it tails logcat for KOReader "opening file" and
POWERHINT "screen on" events) — it does not poll on a timer, so it has no
measurable battery impact.

The module also re-applies `show_temperature_warning = 0` on every boot (see
[tweak 02](02-suppress-temperature-warnings.md)).

## Steps

The module files are in `files/sleep_cover/` in this repo.

### 1. Stage files on the device

```sh
adb push files/sleep_cover/module.prop      /data/local/tmp/sc_module.prop
adb push files/sleep_cover/service.sh       /data/local/tmp/sc_service.sh
adb push files/sleep_cover/cover_watcher.sh /data/local/tmp/sc_cover_watcher.sh
adb push files/sleep_cover/cover_handler.sh /data/local/tmp/sc_cover_handler.sh
```

> **Why stage first?** ADB push cannot write directly into `/data/adb/` even as
> root. Files pushed via ADB get a SELinux context (`shell_data_file`) that is
> rejected when copying into the Magisk modules directory (`magisk_file`). Staging
> in `/data/local/tmp/` and using `cat` redirects (which inherit the destination
> context) works around this. See
> [nook-gl4plus-research/magisk/installation-notes.md](https://github.com/backcountrymountains/nook-gl4plus-research/blob/master/magisk/installation-notes.md)
> for the full explanation.

### 2. Install as root using cat redirects

```sh
adb shell su -c 'mkdir -p /data/adb/modules/sleep_cover'
adb shell su -c 'cat /data/local/tmp/sc_module.prop      > /data/adb/modules/sleep_cover/module.prop'
adb shell su -c 'cat /data/local/tmp/sc_service.sh       > /data/adb/modules/sleep_cover/service.sh'
adb shell su -c 'cat /data/local/tmp/sc_cover_watcher.sh > /data/adb/modules/sleep_cover/cover_watcher.sh'
adb shell su -c 'cat /data/local/tmp/sc_cover_handler.sh > /data/adb/modules/sleep_cover/cover_handler.sh'
adb shell su -c 'chmod 755 /data/adb/modules/sleep_cover/service.sh \
                            /data/adb/modules/sleep_cover/cover_watcher.sh \
                            /data/adb/modules/sleep_cover/cover_handler.sh'
```

### 3. Clean up staging

```sh
adb shell rm /data/local/tmp/sc_*.sh /data/local/tmp/sc_module.prop
```

### 4. Reboot

```sh
adb reboot
```

Magisk runs `service.sh` on every boot, which starts the cover watcher.

## Verify

After reboot, open a book in KOReader (to generate `sleep_cover.png`), then check
the watcher is running:

```sh
adb shell su -c 'grep -rl KOReader /proc/*/cmdline 2>/dev/null'
# Should print one or more /proc/<pid>/cmdline paths
```

> `cover_watcher.sh` runs as `sh` — it does not appear by name in `ps`. The
> reliable indicator is its child `logcat -s KOReader:I POWERHINT:I` process,
> which is what the above command finds.

Lock the screen and check that your book cover is now the sleep image.

## Undo

```sh
adb shell su -c 'rm -rf /data/adb/modules/sleep_cover'
adb reboot
```

## Note on slide-to-unlock

An earlier version of this module also suppressed the Nook's slide-to-unlock
screen. We removed that feature because the device was waking in transit (bag or
pocket) and silently turning pages — the slide-to-unlock acts as a useful
accidental-input guard. If you keep the device in a fixed location and find the
slide-to-unlock screen annoying, see
[nook-gl4plus-research/power-management.md](https://github.com/backcountrymountains/nook-gl4plus-research/blob/master/power-management.md)
for instructions to add it back.
