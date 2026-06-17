#!/usr/bin/env bash
# Rebuild all Magisk module zips with the correct v24 installer format.
# Run from the repo root:  bash scripts/build_zips.sh

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUILD=/tmp/magisk-build
rm -rf "$BUILD"
mkdir -p "$BUILD"

# ---------------------------------------------------------------------------
# Shared installer files (same for every module)
# ---------------------------------------------------------------------------
# update-binary: sources Magisk util_functions and calls install_module.
# OUTFD and ZIPFILE are positional args passed by the Magisk installer.
mkdir -p "$BUILD/META-INF/com/google/android"

cat > "$BUILD/META-INF/com/google/android/update-binary" << 'ENDSCRIPT'
#!/sbin/sh
OUTFD=$2
ZIPFILE=$3
MAGISKBIN=/data/adb/magisk
[ -f "$MAGISKBIN/util_functions.sh" ] || { echo "Magisk not found at $MAGISKBIN"; exit 1; }
. "$MAGISKBIN/util_functions.sh"
install_module
exit 0
ENDSCRIPT

printf '#MAGISK\n' > "$BUILD/META-INF/com/google/android/updater-script"

# ---------------------------------------------------------------------------
# Helper: build a zip from a staging directory
# ---------------------------------------------------------------------------
build_zip() {
    local STAGE="$1"
    local OUT="$2"
    rm -f "$OUT"
    ( cd "$STAGE" && zip -r "$OUT" . )
    echo "Built: ${OUT#$REPO_ROOT/}"
}

# ---------------------------------------------------------------------------
# Module: block-ota (tweak 01)
# ---------------------------------------------------------------------------
STAGE="$BUILD/block-ota"
mkdir -p "$STAGE/META-INF/com/google/android"
cp "$BUILD/META-INF/com/google/android/update-binary"  "$STAGE/META-INF/com/google/android/"
cp "$BUILD/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"

cat > "$STAGE/module.prop" << 'EOF'
id=nook_block_ota
name=Nook GL4 Plus — Block OTA Updates
version=v1
versionCode=1
author=backcountrymountains
description=Disables B&N OTA update components and redirects the update server to localhost on every boot.
EOF

cat > "$STAGE/service.sh" << 'EOF'
#!/system/bin/sh
# Run by Magisk as root after every boot.
# All operations are idempotent — safe to re-run.

# Disable OTA update components.
pm disable com.nook.partner/.otamanager.OtaIntentService  >/dev/null 2>&1
pm disable com.nook.partner/.otamanager.SideloadInstaller >/dev/null 2>&1
pm disable com.nook.partner/.oobe.OobeOtaActivity         >/dev/null 2>&1

# Redirect the OTA server URL to localhost.
echo 'http://127.0.0.1/' > /sdcard/ota_server.conf
EOF

# customize.sh: auto-extraction defaults files to 0644; fix service.sh to 0755.
cat > "$STAGE/customize.sh" << 'EOF'
set_perm "$MODPATH/service.sh" root root 0755
EOF

build_zip "$STAGE" "$REPO_ROOT/files/nook-gl4plus-block-ota-v1.zip"

# ---------------------------------------------------------------------------
# Module: suppress-temp (tweak 02)
# ---------------------------------------------------------------------------
STAGE="$BUILD/suppress-temp"
mkdir -p "$STAGE/META-INF/com/google/android"
cp "$BUILD/META-INF/com/google/android/update-binary"  "$STAGE/META-INF/com/google/android/"
cp "$BUILD/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"

cat > "$STAGE/module.prop" << 'EOF'
id=nook_suppress_temp
name=Nook GL4 Plus — Suppress Temperature Warnings
version=v1
versionCode=1
author=backcountrymountains
description=Disables the nookPartner and SystemUI temperature warning dialogs on every boot.
EOF

cat > "$STAGE/service.sh" << 'EOF'
#!/system/bin/sh
# Run by Magisk as root after every boot.
# All operations are idempotent — safe to re-run.

# Disable the nookPartner temperature warning layer.
pm disable com.nook.partner/.statusbar.StatusBarService >/dev/null 2>&1
am force-stop com.nook.partner >/dev/null 2>&1

# Suppress the SystemUI temperature warning layer.
settings put global show_temperature_warning 0
EOF

cat > "$STAGE/customize.sh" << 'EOF'
set_perm "$MODPATH/service.sh" root root 0755
EOF

build_zip "$STAGE" "$REPO_ROOT/files/nook-gl4plus-suppress-temp-v1.zip"

# ---------------------------------------------------------------------------
# Module: keyremap (tweak 03)
# System overlay only — no service.sh.
# Magisk auto-extracts and applies 0755/0644 defaults, which is exactly
# correct for keylayout files. No customize.sh needed.
# ---------------------------------------------------------------------------
STAGE="$BUILD/keyremap"
mkdir -p "$STAGE/META-INF/com/google/android"
cp "$BUILD/META-INF/com/google/android/update-binary"  "$STAGE/META-INF/com/google/android/"
cp "$BUILD/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"

cat > "$STAGE/module.prop" << 'EOF'
id=nook_gl4plus_keyremap
name=Nook GL4 Plus — Key Remap
version=v1
versionCode=1
author=backcountrymountains
description=Systemlessly overlays a patched Generic.kl to remap the GL4 Plus hardware buttons.
EOF

# Extract Generic.kl from the existing zip (binary file — can't use heredoc)
mkdir -p "$STAGE/system/usr/keylayout"
unzip -p "$REPO_ROOT/files/patches/nook-gl4plus-keyremap-v1.zip" \
    system/usr/keylayout/Generic.kl > "$STAGE/system/usr/keylayout/Generic.kl"

build_zip "$STAGE" "$REPO_ROOT/files/patches/nook-gl4plus-keyremap-v1.zip"

# ---------------------------------------------------------------------------
# Module: sleep-cover (tweak 04)
# Multiple executable scripts.
# ---------------------------------------------------------------------------
STAGE="$BUILD/sleep-cover"
mkdir -p "$STAGE/META-INF/com/google/android"
cp "$BUILD/META-INF/com/google/android/update-binary"  "$STAGE/META-INF/com/google/android/"
cp "$BUILD/META-INF/com/google/android/updater-script" "$STAGE/META-INF/com/google/android/"

# Extract module files from existing zip
for f in module.prop service.sh cover_watcher.sh cover_handler.sh; do
    unzip -p "$REPO_ROOT/files/sleep_cover/nook-gl4plus-sleep-cover-v1.zip" "$f" > "$STAGE/$f"
done

cat > "$STAGE/customize.sh" << 'EOF'
set_perm "$MODPATH/service.sh"       root root 0755
set_perm "$MODPATH/cover_watcher.sh" root root 0755
set_perm "$MODPATH/cover_handler.sh" root root 0755
EOF

build_zip "$STAGE" "$REPO_ROOT/files/sleep_cover/nook-gl4plus-sleep-cover-v1.zip"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$BUILD"
echo "Done."
