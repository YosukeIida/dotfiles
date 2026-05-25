-- torabo-tsuki が接続されたら Karabiner profile を "trabo-tsuki" に、
-- 外したら "Default profile" に自動で戻す。
--
-- Karabiner-Elements 自体には接続デバイスに応じた profile 切替機能が無いため、
-- hs.usb.watcher で接続/切断を検知して karabiner_cli を叩く。
-- 動作確認用に ~/.hammerspoon/usb_keyboard_profile.log にも 1 行ずつ記録する。

local M = {}

local KARABINER_CLI = "/opt/homebrew/bin/karabiner_cli"
local LOG_PATH = os.getenv("HOME") .. "/.hammerspoon/usb_keyboard_profile.log"

-- 判定キー: productName を主、vendor+product ID を保険として OR で照合
local TORABO_TSUKI_PRODUCT_NAME = "_BMP_torabo_tsuki"
local TORABO_TSUKI_VENDOR_ID = 65261 -- 0xFEED
local TORABO_TSUKI_PRODUCT_ID = 48301 -- 0xBCAD

local TORABO_TSUKI_PROFILE = "trabo-tsuki"
local DEFAULT_PROFILE = "Default profile"

local function log(fmt, ...)
  local f = io.open(LOG_PATH, "a")
  if not f then
    return
  end
  f:write(string.format("[%s] " .. fmt .. "\n", os.date("%Y-%m-%d %H:%M:%S"), ...))
  f:close()
end

-- profile 名にスペースが含まれるので POSIX 単一引用符でクォート。
-- Lua の %q だと Hammerspoon の hs.execute 経由でシェルに渡したとき
-- "Default profile" の前半だけ抜けて [error] `Default` is not found. になる。
local function shellQuote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function selectProfile(name)
  local cmd = string.format("%s --select-profile %s 2>&1", KARABINER_CLI, shellQuote(name))
  local output, ok, _, rc = hs.execute(cmd, true)
  log("selectProfile name=%q ok=%s rc=%s output=%q", name, tostring(ok), tostring(rc), tostring(output or ""))
  if not ok or rc ~= 0 then
    hs.printf("[usb_keyboard_profile] failed to select profile %q: %s", name, tostring(output))
  end
end

local function isToraboTsuki(dev)
  if not dev then
    return false
  end
  return dev.productName == TORABO_TSUKI_PRODUCT_NAME
    or (dev.vendorID == TORABO_TSUKI_VENDOR_ID and dev.productID == TORABO_TSUKI_PRODUCT_ID)
end

local function currentlyConnected()
  for _, dev in ipairs(hs.usb.attachedDevices() or {}) do
    if isToraboTsuki(dev) then
      return true
    end
  end
  return false
end

function M.syncProfile()
  local connected = currentlyConnected()
  log("syncProfile: connected=%s", tostring(connected))
  if connected then
    selectProfile(TORABO_TSUKI_PROFILE)
  else
    selectProfile(DEFAULT_PROFILE)
  end
end

M.watcher = hs.usb.watcher.new(function(event)
  if not isToraboTsuki(event) then
    return
  end
  log("watcher event=%s productName=%q", tostring(event.eventType), tostring(event.productName or ""))
  if event.eventType == "added" then
    selectProfile(TORABO_TSUKI_PROFILE)
  elseif event.eventType == "removed" then
    selectProfile(DEFAULT_PROFILE)
  end
end)
M.watcher:start()

-- 起動直後・hs.reload 直後に現状と profile を一致させる
M.syncProfile()

return M
