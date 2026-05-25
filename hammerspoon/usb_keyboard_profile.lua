-- torabo-tsuki が接続されたら Karabiner profile を "trabo-tsuki" に、
-- 外したら "Default profile" に自動で戻す。
--
-- Karabiner-Elements 自体には接続デバイスに応じた profile 切替機能が無いため、
-- hs.usb.watcher で接続/切断を検知して karabiner_cli を叩く。

local M = {}

local KARABINER_CLI = "/opt/homebrew/bin/karabiner_cli"

-- 判定キー: productName を主、vendor+product ID を保険として OR で照合
local TORABO_TSUKI_PRODUCT_NAME = "_BMP_torabo_tsuki"
local TORABO_TSUKI_VENDOR_ID = 65261 -- 0xFEED
local TORABO_TSUKI_PRODUCT_ID = 48301 -- 0xBCAD

local TORABO_TSUKI_PROFILE = "trabo-tsuki"
local DEFAULT_PROFILE = "Default profile"

local function selectProfile(name)
  local cmd = string.format("%s --select-profile %q", KARABINER_CLI, name)
  local _, ok = hs.execute(cmd, true)
  if not ok then
    hs.printf("[usb_keyboard_profile] failed to select profile: %s", name)
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
  if currentlyConnected() then
    selectProfile(TORABO_TSUKI_PROFILE)
  else
    selectProfile(DEFAULT_PROFILE)
  end
end

M.watcher = hs.usb.watcher.new(function(event)
  if not isToraboTsuki(event) then
    return
  end
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
