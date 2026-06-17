#!/usr/bin/env bash
ADB="adb -H 192.168.1.92 -P 5037"

echo "=== Searching all shell scripts on device for 'pm disable' ==="
$ADB shell "su -c 'grep -r \"pm disable\" /data /sdcard 2>/dev/null'"

echo ""
echo "=== Checking Magisk module list from DB ==="
$ADB shell "su -c 'magisk --sqlite \"SELECT name,version,versionCode FROM modules\"'"

echo ""
echo "=== Listing ALL entries under /data/adb/modules (including hidden) ==="
$ADB shell "su -c 'ls -la /data/adb/modules/'"

echo ""
echo "=== Checking for any .sh files registered with Magisk ==="
$ADB shell "su -c 'find /data/adb -type f -name \"*.sh\" 2>/dev/null'"
