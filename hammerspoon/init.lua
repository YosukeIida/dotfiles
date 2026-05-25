-- ~/.hammerspoon/init.lua
local window_manager = require("window_manager")
local urlevent = require("hs.urlevent")
require("usb_keyboard_profile")

-- Raycast -> open "hammerspoon://window_manager?cmd=..."
local function handle_window_manager_url(_, params)
  local cmd = params["cmd"]

  -- legacy named-layout params
  local layout = params["layout"]

  -- numbered-layout params
  local id = params["id"]
  local title = params["title"]
  local description = params["desc"] or params["description"]
  local force = params["force"] == "1"

  if cmd == "ping" then
    window_manager.ping()
  elseif cmd == "reload" then
    hs.reload()

  -- ----- legacy (name-based) -----
  elseif cmd == "apply" then
    window_manager.applyLayoutByName(layout)
  elseif cmd == "save" then
    window_manager.saveAllToLayout(layout) -- layout=AUTO なら window_manager 側で推定
  elseif cmd == "upsert_active" then
    -- Raycastがフォーカスを奪う瞬間を避ける
    hs.timer.doAfter(0.2, function()
      window_manager.upsertFocusedWindowToLayout(layout)
    end)
  elseif cmd == "suggest" then
    window_manager.showSuggestedLayout()

  -- ----- numbered (id-based) -----
  elseif cmd == "layout_new" then
    window_manager.layoutNew(title, description)
  elseif cmd == "layout_update" then
    window_manager.layoutUpdate(id)
  elseif cmd == "layout_upsert_active" then
    hs.timer.doAfter(0.2, function()
      window_manager.layoutUpsertActive(id)
    end)
  elseif cmd == "layout_apply" then
    window_manager.layoutApply(id, { force = force })
  elseif cmd == "layout_apply_auto" then
    local ok = window_manager.layoutApplyAuto()
    if not ok then
      hs.alert.show("No matching layout")
    end
  elseif cmd == "layout_rename" then
    window_manager.layoutRename(id, title, description)
  end
end

urlevent.bind("window_manager", handle_window_manager_url)

-- Optional hotkeys (Raycastなしで即適用)
local HOTKEY_LAYOUT_MAC = "001" -- ctrl+option+B
local HOTKEY_LAYOUT_OMEN = "002" -- ctrl+option+M
hs.hotkey.bind({ "ctrl", "alt" }, "B", function()
  window_manager.layoutApply(HOTKEY_LAYOUT_MAC, { force = true })
end)
hs.hotkey.bind({ "ctrl", "alt" }, "M", function()
  window_manager.layoutApply(HOTKEY_LAYOUT_OMEN, { force = true })
end)

-- 自動適用（ディスプレイ変化時のみ）
window_manager.startAutoWatchers()
window_manager._markInitLoaded()
