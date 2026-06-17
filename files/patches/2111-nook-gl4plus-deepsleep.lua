--[[
   nook-gl4plus-deepsleep
   KOReader patch for the Nook Glowlight 4 Plus (bnrv1300)

   Puts the device into AllWinner hardware deep sleep after each page turn,
   giving weeks of standby battery life rather than hours. Handles the
   single-button wake-to-page-turn problem that arises from Android's wakeup
   key consumption, and preserves correct button direction under 180° screen
   rotation.

   BASED ON nopowen v20231105 by NiLuJe
   https://www.mobileread.com/forums/showthread.php?t=347529
   The deep sleep mechanism (power_enhance_enable via JNI Settings.System),
   the UIManager.show hook, and the onGotoViewRel wrapping pattern are all
   from nopowen. Original additions in this patch:
     - /dev/input fd monitoring + 100ms poll timer to detect which button
       woke the device from deep sleep (first-press path)
     - Rotation-aware page direction (get_rotation_aware_diff)
     - ReaderMenu key binding cleanup
     - Key remapping delegated to settings/event_map.lua

   PREREQUISITES — see README.md for step-by-step install instructions:
     1. /system/usr/keylayout/Generic.kl must map scan codes 193/194 → MENU
        and 191/192 → BACK (requires root; factory maps 193/194 → VOLUME_DOWN
        or F9/F12 which are not wake keys).
     2. settings/event_map.lua must be installed to /sdcard/koreader/settings/
        to remap MENU → LPgFwd and BACK → LPgBack so KOReader's rotation and
        button-invert logic applies to both buttons.
     3. This file must be in /sdcard/koreader/patches/

   The filename prefix 2111 is a load-order key. KOReader sorts patch files
   alphanumerically and loads them in order. 2111 ensures this patch loads
   after KOReader's core modules (UIManager, Device, etc.) are initialised.
   See README.md for more detail.

   License: same terms as nopowen (MIT — keep attribution, do what you want)
--]]

--[[ CONFIG ]]

-- Set ActualSleep = false to test everything except the actual sleep call.
-- The device stays awake; useful for log inspection via ADB.
local ActualSleep = true

-- Seconds to wait after a page turn before entering deep sleep.
local DS_DELAY_PAGES = 1

-- Seconds to wait after a book first opens. Larger than DS_DELAY_PAGES
-- to let the reader UI fully settle before the first sleep.
local DS_DELAY_INTERCEPT = 4

-- If true, show a UI error if the Settings.System write fails.
-- Requires the "Modify system settings" permission granted to KOReader.
local SCHEDULED_SET_ALLOWED_UI_MESSAGE = true


--[[ DEPENDENCIES ]]

local logger  = require("logger")
local android = require("android")
local ffi     = require("ffi")
local C       = ffi.C

local function loclog(msg)
    if logger ~= nil then
        logger.info("KRP: " .. msg)
    end
end

-- KOReader's posix and linux_input FFI headers are already loaded by
-- frontend/device/android/input_android.lua at startup. pcall(require)
-- is idempotent — returns the cached module without reloading.
-- These provide: C.open, C.read, C.O_RDONLY, C.O_NONBLOCK,
--                C.EV_KEY, struct input_event (correct size for this arch).
pcall(require, "ffi/posix_h")
pcall(require, "ffi/linux_input_h")

-- Linux EV_KEY scan codes as reported by the gpio-keys kernel driver,
-- before any Android keycode translation by Generic.kl.
-- The device has four physical buttons: two on each side edge, mirrored
-- top/bottom so either hand can page forward or back when held one-handed.
local WAKE_KEY_FWD  = { [193] = true, [194] = true }  -- bottom-left + bottom-right → forward
local WAKE_KEY_BACK = { [191] = true, [192] = true }  -- top-left    + top-right    → back

-- Pre-open all /dev/input/event* nodes at patch load time.
-- Each open() call creates an independent kernel ring buffer. Android reading
-- the wake-key event from its own fd does NOT consume our copy — so we can
-- determine which button woke the device even though Android's
-- PhoneWindowManager pre-dispatched the key and never placed it in KOReader's
-- AInputQueue. Events accumulate in these buffers; we drain them before each
-- deep sleep so the first post-wake read is unambiguous.
local wake_event_fds = {}
do
    local flags = C.O_RDONLY + C.O_NONBLOCK
    for i = 0, 9 do
        local path = "/dev/input/event" .. i
        local fd = C.open(path, flags)
        if fd >= 0 then
            wake_event_fds[#wake_event_fds + 1] = fd
            loclog("wake monitor: opened " .. path .. " fd=" .. tostring(fd))
        end
    end
    if #wake_event_fds == 0 then
        loclog("wake monitor: no /dev/input/event* opened — check permissions; two-press mode active")
    end
end

local EV_BUF_COUNT   = 32
local ev_buf         = ffi.new("struct input_event[32]")
local ev_struct_size = ffi.sizeof("struct input_event")

local function drain_wake_fds()
    for _, fd in ipairs(wake_event_fds) do
        while C.read(fd, ev_buf, ev_struct_size * EV_BUF_COUNT) > 0 do end
    end
    loclog("wake monitor: input buffers drained")
end

local function read_wake_direction()
    -- Non-blocking read across all fds. Returns "forward", "back", or nil.
    for _, fd in ipairs(wake_event_fds) do
        local n = C.read(fd, ev_buf, ev_struct_size * EV_BUF_COUNT)
        if n and n > 0 then
            local count = math.floor(tonumber(n) / ev_struct_size)
            for j = 0, count - 1 do
                if ev_buf[j].type == C.EV_KEY and ev_buf[j].value == 1 then
                    local code = tonumber(ev_buf[j].code)
                    if WAKE_KEY_FWD[code] then
                        loclog("wake monitor: forward button (code=" .. code .. ")")
                        return "forward"
                    end
                    if WAKE_KEY_BACK[code] then
                        loclog("wake monitor: back button (code=" .. code .. ")")
                        return "back"
                    end
                end
            end
        end
    end
    return nil
end

-- Set by InterceptReaderWidget when a book is opened.
local active_page_handler = nil

-- True from the moment power_enhance_enable=1 is set until a page turn fires.
-- Prevents the poll timer from acting on button presses while the device is
-- already awake (those are handled by AInputQueue normally).
local is_deep_sleep_pending = false

-- Device is used by get_rotation_aware_diff to read rotation state.
-- Key remapping (MENU→LPgFwd, BACK→LPgBack) is handled by
-- /sdcard/koreader/settings/event_map.lua, which KOReader loads during
-- Input:init() — the correct device-specific path for key remapping.
local Device = require("device")


--[[ JNI HELPERS (from nopowen) ]]

function JniExceptCheck(jni)
    if jni.env[0].ExceptionCheck(jni.env) == ffi.C.JNI_TRUE then
        loclog("JNI exception occurred")
        jni.env[0].ExceptionDescribe(jni.env)
        jni.env[0].ExceptionClear(jni.env)
        return true
    end
    return false
end

function JniChecked_CallStaticBooleanMethod(jni, class, method, signature, ...)
    local clazz    = jni.env[0].FindClass(jni.env, class)
    local methodID = jni.env[0].GetStaticMethodID(jni.env, clazz, method, signature)
    local res      = jni.env[0].CallStaticBooleanMethod(jni.env, clazz, methodID, ...)
    local exc      = JniExceptCheck(jni)
    jni.env[0].DeleteLocalRef(jni.env, clazz)
    return exc and false or res, exc
end

function JniChecked_CallStaticIntMethod(jni, class, method, signature, ...)
    local clazz    = jni.env[0].FindClass(jni.env, class)
    local methodID = jni.env[0].GetStaticMethodID(jni.env, clazz, method, signature)
    local res      = jni.env[0].CallStaticIntMethod(jni.env, clazz, methodID, ...)
    local exc      = JniExceptCheck(jni)
    jni.env[0].DeleteLocalRef(jni.env, clazz)
    return res, exc
end

local function android_settings_system_set_int(setting_name, value)
    if android and android.jni and android.app then
        return android.jni:context(android.app.activity.vm, function(jni)
            loclog("set [" .. setting_name .. "] = " .. value)
            local resolver = jni:callObjectMethod(
                android.app.activity.clazz, "getContentResolver",
                "()Landroid/content/ContentResolver;")
            local ok, exc = JniChecked_CallStaticBooleanMethod(jni,
                "android/provider/Settings$System", "putInt",
                "(Landroid/content/ContentResolver;Ljava/lang/String;I)Z",
                resolver, jni.env[0].NewStringUTF(jni.env, setting_name),
                ffi.cast("int32_t", value))
            return ok, exc
        end)
    end
end

local function android_settings_system_get_int(setting_name, defvalue)
    if android and android.jni and android.app then
        return android.jni:context(android.app.activity.vm, function(jni)
            local resolver = jni:callObjectMethod(
                android.app.activity.clazz, "getContentResolver",
                "()Landroid/content/ContentResolver;")
            local val, exc = JniChecked_CallStaticIntMethod(jni,
                "android/provider/Settings$System", "getInt",
                "(Landroid/content/ContentResolver;Ljava/lang/String;I)I",
                resolver, jni.env[0].NewStringUTF(jni.env, setting_name),
                ffi.cast("int32_t", defvalue))
            if exc then val = defvalue end
            return val, exc
        end)
    end
end


--[[ DEEP SLEEP CONTROL ]]

local UIManager = require("ui/uimanager")
local UIManager_show_original           = UIManager.show
local UIManager_broadcastEvent_original = UIManager.broadcastEvent
local InfoMessage = require("ui/widget/infomessage")

local function power_enhance_enable_set(value, allow_ui_error_message)
    if not ActualSleep then return true end
    local ok = android_settings_system_set_int("power_enhance_enable", value)
    if ok then return true end
    loclog("failed to set power_enhance_enable — check 'Modify system settings' permission")
    if allow_ui_error_message then
        pcall(UIManager_show_original, UIManager, InfoMessage:new{
            text = "KRP: power_enhance_enable write failed.\n" ..
                   "Grant 'Modify system settings' to KOReader." })
    end
    return false
end

local function deepsleep_reset(allow_ui_error_message)
    loclog("deepsleep_reset: power_enhance_enable=0")
    power_enhance_enable_set(0, allow_ui_error_message)
end

local function delayed_deepsleep(allow_ui_error_message)
    loclog("delayed_deepsleep: power_enhance_enable=1")
    is_deep_sleep_pending = true
    drain_wake_fds()
    power_enhance_enable_set(1, allow_ui_error_message)
end

local function deepsleep_schedule(seconds)
    UIManager:unschedule(delayed_deepsleep)
    loclog("scheduling deep sleep in " .. seconds .. "s")
    UIManager:scheduleIn(seconds, delayed_deepsleep, SCHEDULED_SET_ALLOWED_UI_MESSAGE)
end


--[[ ROTATION-AWARE PAGE DIRECTION ]]

-- Returns the correct onGotoViewRel diff (+1 forward, -1 back) for a
-- physical button press, accounting for screen rotation and the user's
-- "invert page turn buttons" setting.
--
-- How it works:
--   event_map[82] (MENU keycode) = "LPgFwd" normally, "LPgBack" if the user
--   has inverted buttons via KOReader's reader menu. This base value is set
--   by settings/event_map.lua and then toggled by Device:invertButtons().
--
--   rotation_map[current_rotation] swaps LPgFwd↔LPgBack when the screen is
--   rotated 180° (DEVICE_ROTATED_UPSIDE_DOWN), ensuring the physically-lower
--   button always pages forward regardless of orientation.
--
--   Both factors are read here so the poll-timer (first-press) path matches
--   what the AInputQueue (second-press) path does through KOReader's normal
--   event pipeline.
local function get_rotation_aware_diff(scan_is_fwd)
    local mapped = Device.input.event_map[82] or "LPgFwd"
    local rota   = Device.screen:getRotationMode()
    local rmap   = Device.input.rotation_map and Device.input.rotation_map[rota]
    local final  = (rmap and rmap[mapped]) or mapped
    local fwd    = (final == "LPgFwd") and 1 or -1
    return scan_is_fwd and fwd or -fwd
end


--[[ POLL TIMER ]]

-- WHY THIS EXISTS:
-- When the device is in AllWinner deep sleep (power_enhance_enable=1), the
-- first button press wakes the CPU but is intercepted by Android's
-- PhoneWindowManager for wakeup (AInputQueue_preDispatchEvent returns
-- non-zero). ALooper_pollOnce returns EINTR with no Lua-level events.
-- APP_CMD_RESUME is never delivered because the vendor's "Sleep Screen lock"
-- re-suspends the device (~500ms after wake) before the Activity lifecycle
-- can run. The second press reaches KOReader normally.
--
-- This timer fires every 100ms. After ALooper_pollOnce returns EINTR,
-- UIManager checks scheduled tasks immediately — the timer fires within
-- the ~500ms wake window. It reads the /dev/input buffer (which still
-- holds the wake key event because our fd is independent of Android's)
-- and fires the page turn directly.
local function poll_wake_key()
    if active_page_handler and is_deep_sleep_pending then
        local direction = read_wake_direction()
        if direction then
            is_deep_sleep_pending = false
            local diff = get_rotation_aware_diff(direction == "forward")
            loclog("poll: " .. direction .. " → diff=" .. diff)
            UIManager:scheduleIn(0.15, function()
                local ok, err = pcall(active_page_handler.onGotoViewRel,
                                      active_page_handler, diff)
                if not ok then
                    loclog("poll: page turn failed: " .. tostring(err))
                    deepsleep_schedule(DS_DELAY_PAGES)
                end
            end)
        end
    end
    UIManager:scheduleIn(0.1, poll_wake_key)
end


--[[ RESUME HOOK (belt-and-suspenders) ]]

-- APP_CMD_RESUME is never delivered on this vendor's power_enhance_enable
-- sleep path. This hook is kept in case of firmware variation or future
-- firmware updates that restore the standard Activity lifecycle.
UIManager.broadcastEvent = function(self, event, ...)
    local result = UIManager_broadcastEvent_original(self, event, ...)
    if event and event.handler == "onResume" then
        loclog("Resume event — resetting power_enhance_enable=0")
        is_deep_sleep_pending = false
        deepsleep_reset(false)
        local direction = active_page_handler and read_wake_direction()
        if direction then
            local diff = get_rotation_aware_diff(direction == "forward")
            loclog("Resume: page turn diff=" .. diff)
            UIManager:scheduleIn(0.15, function()
                local ok, err = pcall(active_page_handler.onGotoViewRel,
                                      active_page_handler, diff)
                if not ok then
                    loclog("Resume: page turn failed: " .. tostring(err))
                    deepsleep_schedule(DS_DELAY_PAGES)
                end
            end)
        else
            deepsleep_schedule(DS_DELAY_PAGES)
        end
    end
    return result
end


--[[ READER WIDGET INTERCEPT ]]

local function InterceptReaderWidget(Widget)
    local pageHandler = Widget.paging
    if pageHandler == nil then
        loclog("no paging found, trying rolling")
        pageHandler = Widget.rolling
        if pageHandler ~= nil then loclog("rolling found!") end
    else
        loclog("paging found!")
    end

    if pageHandler == nil then
        loclog("no paging or rolling found — patch inactive for this document")
        return
    end

    loclog("intercepting onGotoViewRel")
    active_page_handler = pageHandler

    -- settings/event_map.lua maps MENU (82) → LPgFwd and BACK (4) → LPgBack,
    -- so the forward button now generates "LPgFwd" events (not "Menu") and
    -- the back button generates "LPgBack" (not "Back"). ReaderMenu's
    -- PressMenu / KeyPressShowMenu only fire on "Menu" events, so they will
    -- not trigger. Clear them as a safety measure anyway.
    if Widget.menu and Widget.menu.key_events then
        Widget.menu.key_events.PressMenu        = nil
        Widget.menu.key_events.KeyPressShowMenu = nil
        loclog("cleared ReaderMenu Menu key bindings (safety)")
    end

    -- No custom key binding needed for the forward button: settings/event_map.lua
    -- maps MENU → LPgFwd, so the built-in GotoNextPage / GotoPrevPage bindings
    -- (which already listen for LPgFwd / LPgBack) handle second presses.
    -- rotation_map automatically swaps LPgFwd↔LPgBack on 180° rotation for
    -- both buttons.

    local pageHandler_onGotoViewRel_original = pageHandler.onGotoViewRel

    pageHandler.onGotoViewRel = function(self, diff)
        loclog("i_am_paging! diff=" .. tostring(diff))

        -- Disarm the poll timer. This turn is already in progress via either
        -- the poll timer's scheduleIn(0.15) or the AInputQueue second-press.
        is_deep_sleep_pending = false

        deepsleep_reset(false)
        pageHandler_onGotoViewRel_original(self, diff)

        local front_light = android_settings_system_get_int("front_light_mode", -1)
        loclog("front_light_mode=" .. tostring(front_light))

        deepsleep_schedule(DS_DELAY_PAGES)
    end

    loclog("scheduling initial deep sleep after book open")
    deepsleep_reset(false)
    deepsleep_schedule(DS_DELAY_INTERCEPT)

    loclog("starting wake-key poll timer (100ms)")
    UIManager:scheduleIn(0.1, poll_wake_key)
end


--[[ UIMANAGER HOOK — entry point ]]

-- Monitors all widget shows. When ReaderUI appears (book opened), hooks
-- the page handler to wrap deep sleep around every page turn.
UIManager.show = function(self, widget, refreshtype, refreshregion, x, y, refreshdither)
    local title = widget.id or widget.name or tostring(widget)
    loclog("widget showing: " .. title)
    local result = UIManager_show_original(self, widget, refreshtype, refreshregion, x, y, refreshdither)
    if title == "ReaderUI" then
        loclog("ReaderUI detected — intercepting")
        InterceptReaderWidget(widget)
    end
    return result
end
