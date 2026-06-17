#!/usr/bin/env bash
# Verify that the installed Magisk modules have re-applied all expected changes.
# Run this after installing module zips and rebooting.
#
# Usage:  bash scripts/verify_modules.sh

ADB="adb -H 192.168.1.92 -P 5037"
PASS=0
FAIL=0

pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL + 1)); }

echo "=== Verify: Magisk modules applied expected changes ==="

DISABLED=$($ADB shell "dumpsys package com.nook.partner" | tr -d '\r')

# Tweak 01 — OTA block
for comp in "OtaIntentService" "SideloadInstaller" "OobeOtaActivity"; do
    if echo "$DISABLED" | grep -q "$comp"; then
        pass "$comp is disabled  [tweak 01]"
    else
        fail "$comp is NOT disabled  [tweak 01 — module may not have run]"
    fi
done

OTA_CONF=$($ADB shell "cat /sdcard/ota_server.conf 2>/dev/null || echo __ABSENT__" | tr -d '\r')
if echo "$OTA_CONF" | grep -q "127.0.0.1"; then
    pass "ota_server.conf points to 127.0.0.1  [tweak 01]"
else
    fail "ota_server.conf missing or wrong: $OTA_CONF  [tweak 01]"
fi

# Tweak 02 — temperature suppression
if echo "$DISABLED" | grep -q "StatusBarService"; then
    pass "StatusBarService is disabled  [tweak 02]"
else
    fail "StatusBarService is NOT disabled  [tweak 02 — module may not have run]"
fi

TEMP_WARN=$($ADB shell "settings get global show_temperature_warning" | tr -d '\r')
if [ "$TEMP_WARN" = "0" ]; then
    pass "show_temperature_warning = 0  [tweak 02]"
else
    fail "show_temperature_warning = $TEMP_WARN (expected 0)  [tweak 02]"
fi

# Module presence sanity check
echo ""
echo "=== Installed Magisk modules ==="
$ADB shell "su -c 'ls /data/adb/modules/'" | tr -d '\r' | while read -r mod; do
    echo "  $mod"
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Check that the module zips were installed and the device was rebooted."
    echo "Module service.sh logs (if any): adb shell su -c 'logcat -d -s Magisk'"
    exit 1
fi
