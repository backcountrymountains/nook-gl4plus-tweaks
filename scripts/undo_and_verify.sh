#!/usr/bin/env bash
# Undo manual tweak changes, reboot, verify the device is at a clean baseline.
# Run this before installing Magisk module zips so you can confirm the module
# itself is responsible for re-applying each change.
#
# Usage:  bash scripts/undo_and_verify.sh

ADB="adb -H 192.168.1.92 -P 5037"
PASS=0
FAIL=0

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL + 1)); }

echo "=== Step 1: Undo manual changes ==="

echo "  Re-enabling OTA components..."
$ADB shell "su -c 'pm enable com.nook.partner/.otamanager.OtaIntentService'"
$ADB shell "su -c 'pm enable com.nook.partner/.otamanager.SideloadInstaller'"
$ADB shell "su -c 'pm enable com.nook.partner/.oobe.OobeOtaActivity'"
$ADB shell "rm -f /sdcard/ota_server.conf"

echo "  Re-enabling temperature warnings..."
$ADB shell "su -c 'pm enable com.nook.partner/.statusbar.StatusBarService'"
$ADB shell "settings put global show_temperature_warning 1"

# Android writes package-restrictions.xml asynchronously after pm enable.
# Rebooting before the write lands loses the change.  Poll until the
# disabled-components block for com.nook.partner no longer contains our
# target components (i.e. they have moved to enabled-components).
echo "  Waiting for package-restrictions.xml to be flushed to disk..."
FLUSH_OK=0
for i in $(seq 1 30); do
    # Extract only items inside <disabled-components>…</disabled-components>
    DISABLED_ITEMS=$($ADB shell "su -c 'cat /data/system/users/0/package-restrictions.xml'" | tr -d '\r' \
        | awk '/<disabled-components>/{f=1; next} /<\/disabled-components>/{f=0} f{print}')
    STILL_DISABLED=0
    for comp in "OtaIntentService" "SideloadInstaller" "OobeOtaActivity" "StatusBarService"; do
        echo "$DISABLED_ITEMS" | grep -q "$comp" && STILL_DISABLED=1 && break
    done
    if [ "$STILL_DISABLED" -eq 0 ]; then
        FLUSH_OK=1
        break
    fi
    sleep 1
done
if [ "$FLUSH_OK" -eq 0 ]; then
    echo "  WARNING: package-restrictions.xml did not update after 30s — reboot may lose the pm enable changes."
fi
echo "  Done."

echo ""
echo "=== Step 2: Reboot ==="
echo "  Rebooting device — this will take ~60s..."
$ADB reboot

echo "  Waiting for ADB to reconnect..."
$ADB wait-for-device

echo "  Waiting for Android to finish booting..."
while true; do
    result=$($ADB shell "getprop sys.boot_completed 2>/dev/null" | tr -d '\r')
    [ "$result" = "1" ] && break
    sleep 5
done
echo "  Device is ready."

echo ""
echo "=== Step 3: Verify baseline ==="

# Read package-restrictions.xml directly — ground truth for persisted state.
# Check that our target components are NOT in the disabled-components block.
DISABLED_ITEMS=$($ADB shell "su -c 'cat /data/system/users/0/package-restrictions.xml'" | tr -d '\r' \
    | awk '/<disabled-components>/{f=1; next} /<\/disabled-components>/{f=0} f{print}')

for comp in "OtaIntentService" "SideloadInstaller" "OobeOtaActivity" "StatusBarService"; do
    if echo "$DISABLED_ITEMS" | grep -q "$comp"; then
        fail "$comp is still in disabled-components on disk (expected enabled)"
    else
        pass "$comp is enabled (not in disabled-components)"
    fi
done

OTA_CONF=$($ADB shell "cat /sdcard/ota_server.conf 2>/dev/null || echo __ABSENT__" | tr -d '\r')
if echo "$OTA_CONF" | grep -q "__ABSENT__"; then
    pass "ota_server.conf is absent"
else
    fail "ota_server.conf still present: $OTA_CONF"
fi

TEMP_WARN=$($ADB shell "settings get global show_temperature_warning" | tr -d '\r')
if [ "$TEMP_WARN" = "1" ]; then
    pass "show_temperature_warning = 1"
else
    fail "show_temperature_warning = $TEMP_WARN (expected 1)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "Baseline is clean. Install the Magisk module zips and reboot, then"
    echo "run scripts/verify_modules.sh to confirm the modules are effective."
else
    echo ""
    echo "Some checks failed — review output above before installing modules."
    exit 1
fi
