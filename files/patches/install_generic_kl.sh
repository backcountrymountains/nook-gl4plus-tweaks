#!/usr/bin/env bash
# install_generic_kl.sh
#
# Patches /system/usr/keylayout/Generic.kl on a Nook Glowlight 4 Plus
# (bnrv1300) to remap the physical buttons to BACK and MENU so they can
# wake the device from AllWinner deep sleep.
#
# REQUIRES ROOT — the /system partition is read-only by default. This
# script uses 'su' via ADB to remount it read-write for the duration of
# the operation and remounts it read-only again immediately after.
#
# Usage:
#   ./install_generic_kl.sh            # apply the patch
#   ./install_generic_kl.sh --restore  # restore from the backup this script created
#
# The backup is stored on the device at:
#   /system/usr/keylayout/Generic.kl.nook-deepsleep-backup
#
# A reboot is required after applying or restoring for the change to take effect.

set -euo pipefail

ADB="${ADB:-adb}"          # override with ADB="adb -H host -P port" if needed
KL_PATH="/system/usr/keylayout/Generic.kl"
BACKUP_PATH="/system/usr/keylayout/Generic.kl.nook-deepsleep-backup"

# ── helpers ───────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

check_adb() {
    $ADB devices | grep -q "device$" || die "No ADB device found. Connect the Nook and ensure ADB is authorised."
}

check_root() {
    $ADB shell "su -c 'id'" 2>/dev/null | grep -q "uid=0" \
        || die "Root access unavailable on the device. This script requires a rooted Nook."
}

remount_rw() { $ADB shell "su -c 'mount -o remount,rw /system'"; }
remount_ro() { $ADB shell "su -c 'mount -o remount,ro /system'"; }

# ── restore mode ──────────────────────────────────────────────────────────────

do_restore() {
    echo "=== Restoring Generic.kl from backup ==="
    check_adb
    check_root

    $ADB shell "su -c 'test -f $BACKUP_PATH'" \
        || die "Backup not found at $BACKUP_PATH. Has install_generic_kl.sh been run before?"

    remount_rw
    $ADB shell "su -c 'cp $BACKUP_PATH $KL_PATH && chmod 644 $KL_PATH'"
    remount_ro

    echo ""
    echo "Restored. Vendor section is now:"
    $ADB shell "su -c 'tail -8 $KL_PATH'"
    echo ""
    echo "Reboot the device for the change to take effect."
    echo "  adb reboot"
}

# ── install mode ──────────────────────────────────────────────────────────────

do_install() {
    echo "=== Patching Generic.kl for nook-gl4plus-deepsleep ==="
    echo ""
    echo "NOTE: This script requires root access on the device."
    echo "      It will remount /system read-write briefly, write one file,"
    echo "      then remount read-only again."
    echo ""
    check_adb
    check_root

    # Check if backup already exists
    if $ADB shell "su -c 'test -f $BACKUP_PATH'" 2>/dev/null; then
        echo "Backup already exists at $BACKUP_PATH — skipping backup step."
        echo "To restore the original, run: $0 --restore"
    else
        echo "Creating backup at $BACKUP_PATH ..."
        remount_rw
        $ADB shell "su -c 'cp $KL_PATH $BACKUP_PATH && chmod 644 $BACKUP_PATH'"
        remount_ro
        echo "Backup created."
    fi

    echo ""
    echo "Current vendor section (before patch):"
    $ADB shell "su -c 'tail -8 $KL_PATH'"
    echo ""

    # Build the patched file on the device using a temp file.
    # Strategy: strip the existing E70P74 define block and append our version.
    # The block always starts with '# E70P74 define' and runs to end-of-file.
    remount_rw
    $ADB shell "su -c '
        # Remove existing E70P74 section (everything from that line onwards)
        grep -n \"# E70P74 define\" $KL_PATH | cut -d: -f1 | head -1 | read LINENUM 2>/dev/null || true
        if [ -n \"\$LINENUM\" ]; then
            head -n \$(( LINENUM - 1 )) $KL_PATH > /data/local/tmp/Generic.kl.tmp
        else
            cp $KL_PATH /data/local/tmp/Generic.kl.tmp
        fi

        # Append the corrected E70P74 section
        cat >> /data/local/tmp/Generic.kl.tmp << '"'"'KLEOF'"'"'

# E70P74 define
# Remapped by nook-gl4plus-deepsleep for AllWinner deep sleep compatibility.
# BACK (191/192) and MENU (193/194) are hardcoded wake keys in Android'"'"'s
# PhoneWindowManager; VOLUME_DOWN and F9-F12 (factory defaults) are not.
# Top-left and top-right buttons (191, 192) -> BACK  -> page back
# Bottom-left and bottom-right buttons (193, 194) -> MENU -> page forward
key 102   HOME
key 191   BACK
key 192   BACK
key 193   MENU
key 194   MENU
KLEOF

        cp /data/local/tmp/Generic.kl.tmp $KL_PATH
        chmod 644 $KL_PATH
        rm /data/local/tmp/Generic.kl.tmp
    '"
    remount_ro

    echo ""
    echo "Patched. Vendor section is now:"
    $ADB shell "su -c 'tail -12 $KL_PATH'"
    echo ""
    echo "Done. Reboot the device for the change to take effect:"
    echo "  adb reboot"
    echo ""
    echo "To restore the original at any time:"
    echo "  $0 --restore"
}

# ── entry point ───────────────────────────────────────────────────────────────

case "${1:-}" in
    --restore|-r)   do_restore ;;
    "")             do_install ;;
    --help|-h)
        echo "Usage: $0 [--restore]"
        echo "  (no args)   Patch Generic.kl and create a backup"
        echo "  --restore   Restore Generic.kl from the backup"
        ;;
    *)  die "Unknown argument: $1. Use --restore or no arguments." ;;
esac
