-- ~/.hammerspoon/window_manager.lua
local M = {}

local pasteboard = require("hs.pasteboard")
local screen = require("hs.screen")
local window = require("hs.window")
local caffeinateWatcher = require("hs.caffeinate.watcher")
local fs = require("hs.fs")
local windowFilter = require("hs.window.filter")

-- Raycastがフォーカスを奪っても「直前の実ウィンドウ」を使えるようにする
local LAST_FOCUSED_STANDARD_WINDOW = nil
local RAYCAST_BUNDLE_ID = "com.raycast.macos"

local function isRaycastApp(app)
  if not app then return false end
  local bid = app:bundleID() or ""
  if bid == RAYCAST_BUNDLE_ID then return true end
  return (app:name() or "") == "Raycast"
end

local function subscribeWindowFocused(attempt)
  attempt = attempt or 1
  local ok, err = pcall(function()
    windowFilter.default:subscribe(windowFilter.windowFocused, function(w)
      if not w then return end
      if not w:isStandard() then return end
      local app = w:application()
      if not app then return end
      if isRaycastApp(app) then return end
      LAST_FOCUSED_STANDARD_WINDOW = w
    end)
  end)
  if not ok then
    if attempt <= 5 then
      hs.timer.doAfter(attempt * 0.5, function() subscribeWindowFocused(attempt + 1) end)
    else
      hs.printf("wm: windowFilter.subscribe failed after %d attempts: %s", attempt, tostring(err))
    end
  end
end
subscribeWindowFocused()

do
  local w = window.focusedWindow()
  if w and w:isStandard() then
    local app = w:application()
    if app and (not isRaycastApp(app)) then
      LAST_FOCUSED_STANDARD_WINDOW = w
    end
  end
end

-- ---------- ユーティリティ ----------
local function round(n, digits)
  local m = 10 ^ (digits or 4)
  return math.floor(n * m + 0.5) / m
end

local function clamp(n, minVal, maxVal)
  if n < minVal then return minVal end
  if n > maxVal then return maxVal end
  return n
end

-- Keep unit rects strict and stable so repeated apply/update cycles stay idempotent.
local function sanitizeUnitRect(unit)
  if type(unit) ~= "table" then return nil end

  local x = tonumber(unit.x)
  local y = tonumber(unit.y)
  local w = tonumber(unit.w)
  local h = tonumber(unit.h)
  if (not x) or (not y) or (not w) or (not h) then return nil end

  local function adjust(ax, ay, aw, ah)
    ax = clamp(ax, 0, 1)
    ay = clamp(ay, 0, 1)
    aw = clamp(aw, 0.01, 1)
    ah = clamp(ah, 0.01, 1)

    if ax + aw > 1 then ax = 1 - aw end
    if ay + ah > 1 then ay = 1 - ah end

    ax = clamp(ax, 0, 1)
    ay = clamp(ay, 0, 1)
    return ax, ay, aw, ah
  end

  x, y, w, h = adjust(x, y, w, h)
  x = round(x, 4)
  y = round(y, 4)
  w = round(w, 4)
  h = round(h, 4)
  x, y, w, h = adjust(x, y, w, h)

  return { x = x, y = y, w = w, h = h }
end

local function stableSortWindows(ws)
  table.sort(ws, function(a, b) return (a:id() or 0) < (b:id() or 0) end)
  return ws
end

local function standardWindowsOfApp(app)
  local ws = {}
  for _, w in ipairs(app:allWindows() or {}) do
    if w:isStandard() then table.insert(ws, w) end
  end
  return stableSortWindows(ws)
end

local function unitRectForWindow(w)
  local wf = w:frame()
  local sf = w:screen():frame()
  return sanitizeUnitRect({
    x = (wf.x - sf.x) / sf.w,
    y = (wf.y - sf.y) / sf.h,
    w = wf.w / sf.w,
    h = wf.h / sf.h,
  })
end

local UNIT_STABILITY_TOLERANCE_PX = 2

local function roundPx(n)
  return math.floor(n + 0.5)
end

local function unitRectToFrame(targetScreen, unit)
  local safeUnit = sanitizeUnitRect(unit)
  if (not targetScreen) or (not safeUnit) then return nil end

  local sf = targetScreen:frame()
  local x = roundPx(sf.x + (sf.w * safeUnit.x))
  local y = roundPx(sf.y + (sf.h * safeUnit.y))
  local w = math.max(1, roundPx(sf.w * safeUnit.w))
  local h = math.max(1, roundPx(sf.h * safeUnit.h))
  local maxX = roundPx(sf.x + sf.w)
  local maxY = roundPx(sf.y + sf.h)

  if x + w > maxX then w = math.max(1, maxX - x) end
  if y + h > maxY then h = math.max(1, maxY - y) end

  return { x = x, y = y, w = w, h = h }
end

local function layoutWindowKey(item)
  return table.concat({
    tostring(item.bundleID or ""),
    tostring(item.windowIndex or ""),
  }, "\31")
end

local function maxUnitDeltaInPixels(targetScreen, a, b)
  local unitA = sanitizeUnitRect(a)
  local unitB = sanitizeUnitRect(b)
  if (not targetScreen) or (not unitA) or (not unitB) then return math.huge end

  local sf = targetScreen:frame()
  return math.max(
    math.abs((unitA.x - unitB.x) * sf.w),
    math.abs((unitA.y - unitB.y) * sf.h),
    math.abs((unitA.w - unitB.w) * sf.w),
    math.abs((unitA.h - unitB.h) * sf.h)
  )
end

local function stabilizeCapturedItem(item, previousByKey)
  if type(item) ~= "table" then return nil end

  local normalized = {
    bundleID = item.bundleID,
    windowIndex = item.windowIndex,
    screenUUID = item.screenUUID,
    unit = sanitizeUnitRect(item.unit),
  }
  if not normalized.unit then return nil end

  local previous = previousByKey and previousByKey[layoutWindowKey(item)] or nil
  if not previous then return normalized end

  local targetScreen = screen.find(normalized.screenUUID) or screen.find(previous.screenUUID)
  if maxUnitDeltaInPixels(targetScreen, previous.unit, normalized.unit) <= UNIT_STABILITY_TOLERANCE_PX then
    normalized.unit = sanitizeUnitRect(previous.unit) or normalized.unit
    normalized.screenUUID = previous.screenUUID or normalized.screenUUID
  end

  return normalized
end

local function stabilizeCapturedWindows(capturedWindows, previousWindows)
  local previousByKey = {}
  for _, item in ipairs(previousWindows or {}) do
    previousByKey[layoutWindowKey(item)] = item
  end

  local stabilized = {}
  for _, item in ipairs(capturedWindows or {}) do
    local normalized = stabilizeCapturedItem(item, previousByKey)
    if normalized then
      table.insert(stabilized, normalized)
    end
  end
  return stabilized
end

local function screenSignature()
  local parts = {}
  for _, s in ipairs(screen.allScreens()) do
    local uuid = s:getUUID() or (s:name() or "unknown")
    local mode = s:currentMode() or {}
    table.insert(parts, string.format("%s:%sx%s@%sx", uuid, mode.w or "?", mode.h or "?", mode.scale or "?"))
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

local function layoutToLua(layout)
  local lines = {}
  table.insert(lines, "return {")
  table.insert(lines, string.format('  signature = %q,', layout.signature))
  table.insert(lines, "  windows = {")
  for _, it in ipairs(layout.windows) do
    table.insert(lines,
      string.format(
        '    { bundleID=%q, windowIndex=%d, screenUUID=%q, unit={x=%.4f,y=%.4f,w=%.4f,h=%.4f} },',
        it.bundleID, it.windowIndex, it.screenUUID,
        it.unit.x, it.unit.y, it.unit.w, it.unit.h
      )
    )
  end
  table.insert(lines, "  }")
  table.insert(lines, "}")
  return table.concat(lines, "\n")
end

local function captureAll()
  local sig = screenSignature()
  local items = {}
  for _, w in ipairs(window.allWindows()) do
    if w:isStandard() then
      local app = w:application()
      if app then
        local bid = app:bundleID() or app:name()
        local ws = standardWindowsOfApp(app)
        local idx = 1
        for i, ww in ipairs(ws) do
          if ww:id() == w:id() then idx = i; break end
        end
        local unit = unitRectForWindow(w)
        if unit then
          table.insert(items, {
            bundleID = bid,
            windowIndex = idx,
            screenUUID = (w:screen():getUUID() or w:screen():name() or "unknown"),
            unit = unit,
          })
        end
      end
    end
  end
  return { signature = sig, windows = items }
end

local function captureFocused()
  local w = window.focusedWindow()

  -- Raycast実行直後は focusedWindow が Raycast になっていたり nil になりがち
  local focusedApp = w and w:application()
  if focusedApp and isRaycastApp(focusedApp) then
    w = nil
  end
  if (not w) or (not w:isStandard()) then
    w = LAST_FOCUSED_STANDARD_WINDOW
  end
  if not w or not w:isStandard() then return nil end

  local app = w:application()
  if not app then return nil end
  if isRaycastApp(app) then return nil end
  local bid = app:bundleID() or app:name()
  local ws = standardWindowsOfApp(app)
  local idx = 1
  for i, ww in ipairs(ws) do
    if ww:id() == w:id() then idx = i; break end
  end
  local unit = unitRectForWindow(w)
  if not unit then return nil end

  return {
    signature = screenSignature(),
    windows = {{
      bundleID = bid,
      windowIndex = idx,
      screenUUID = (w:screen():getUUID() or w:screen():name() or "unknown"),
      unit = unit,
    }}
  }
end

-- ---------- クリップボード出力（デバッグ用に残す） ----------
function M.copyAllWindowsToClipboard()
  local layout = captureAll()
  pasteboard.setContents(layoutToLua(layout))
end

function M.copyFocusedWindowToClipboard()
  local layout = captureFocused()
  if not layout then return end
  local it = layout.windows[1]
  local snippet = string.format(
    '{ bundleID=%q, windowIndex=%d, screenUUID=%q, unit={x=%.4f,y=%.4f,w=%.4f,h=%.4f} },',
    it.bundleID, it.windowIndex, it.screenUUID,
    it.unit.x, it.unit.y, it.unit.w, it.unit.h
  )
  pasteboard.setContents(snippet)
end

-- ---------- 適用（内部） ----------
local lastAppliedSignature = nil

local function loadLayoutByName(name)
  local path = hs.configdir .. "/layouts/" .. name .. ".lua"
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, layout = pcall(chunk)
  if not ok then return nil, layout end
  return layout, nil
end

local function applyLayout(layout)
  if not layout or not layout.windows then return end
  for _, it in ipairs(layout.windows) do
    local app = hs.application.get(it.bundleID) or hs.application.find(it.bundleID)
    if app then
      local ws = standardWindowsOfApp(app)
      local w = ws[it.windowIndex]
      if w then
        local tgt = screen.find(it.screenUUID) or w:screen()
        if tgt then w:moveToScreen(tgt) end
        local unit = sanitizeUnitRect(it.unit)
        local frame = unitRectToFrame(tgt or w:screen(), unit)
        if frame then
          local ok, err = pcall(function() w:setFrame(frame, 0) end)
          if not ok then
            hs.printf("wm: setFrame failed: %s", tostring(err))
          end
        end
      end
    end
  end
end

function M.applyBestLayoutIfNeeded(defaultName)
  local currentSig = screenSignature()
  if lastAppliedSignature == currentSig then return end

  local layout, _ = loadLayoutByName(currentSig)
  if not layout then layout = loadLayoutByName(defaultName) end
  if not layout then
    lastAppliedSignature = currentSig
    return
  end

  applyLayout(layout)
  lastAppliedSignature = currentSig
end

function M.startWatchers(defaultName)
  lastAppliedSignature = screenSignature()

  M._screenWatcher = hs.screen.watcher.new(function()
    M.applyBestLayoutIfNeeded(defaultName)
  end):start()

  M._wakeWatcher = caffeinateWatcher.new(function(ev)
    if ev == caffeinateWatcher.screensDidWake or ev == caffeinateWatcher.systemDidWake then
      M.applyBestLayoutIfNeeded(defaultName)
    end
  end):start()
end

-- ===== Raycast運用向け（ファイル保存 / 推定 / upsert）=====

local function ensureLayoutsDir()
  local dir = hs.configdir .. "/layouts"
  pcall(function() fs.mkdir(dir) end)
  return dir
end

-- status file for Script Commands confirmations
local function ensureStatusDir()
  local dir = (os.getenv("HOME") or "") .. "/.cache/hammerspoon-wm"
  pcall(function() fs.mkdir(dir) end)
  return dir
end

local function writeStatusFile(name, content)
  local dir = ensureStatusDir()
  local path = dir .. "/" .. name
  local f = io.open(path, "w")
  if not f then return false end
  f:write(content)
  f:close()
  return true
end

function M._markInitLoaded()
  writeStatusFile("init_loaded_at", tostring(os.time()))
end

function M.ping()
  hs.alert.show("wm: ok")
end

local function hasBuiltinDisplay()
  local patterns = { "built%-in", "color lcd", "内蔵", "ビルトイン", "retina" }
  for _, s in ipairs(screen.allScreens()) do
    local name = (s:name() or ""):lower()
    for _, p in ipairs(patterns) do
      if name:find(p) then return true end
    end
  end
  return false
end

function M.suggestLayoutName()
  local n = #screen.allScreens()
  local builtin = hasBuiltinDisplay()
  if n == 1 then
    if builtin then return "mac_only" else return "main_display" end
  end
  if builtin then return "main_mac" else return "main_mac" end
end

function M.showSuggestedLayout()
  hs.alert.show("Suggested: " .. M.suggestLayoutName())
end

function M.saveAllToLayout(name)
  if name == nil or name == "" or name == "AUTO" then
    name = M.suggestLayoutName()
    hs.alert.show("Save → " .. name)
  end
  local dir = ensureLayoutsDir()
  local layout = captureAll()
  local out = layoutToLua(layout)
  local path = dir .. "/" .. name .. ".lua"
  local f, err = io.open(path, "w")
  if not f then
    hs.alert.show("Save failed: " .. tostring(err))
    return
  end
  f:write(out)
  f:close()
  hs.alert.show("Saved: " .. name)
end

function M.applyLayoutByName(name)
  if not name or name == "" then
    hs.alert.show("Apply: layout name missing")
    return
  end
  local layout, err = loadLayoutByName(name)
  if not layout then
    hs.alert.show("Load failed: " .. tostring(err))
    return
  end
  applyLayout(layout)
  hs.alert.show("Applied: " .. name)
end

local function loadLayoutTable(name)
  local path = hs.configdir .. "/layouts/" .. name .. ".lua"
  local chunk = loadfile(path)
  if not chunk then return { signature = screenSignature(), windows = {} } end
  local ok, t = pcall(chunk)
  if not ok or type(t) ~= "table" then
    return { signature = screenSignature(), windows = {} }
  end
  t.windows = t.windows or {}
  return t
end

local function writeLayoutTable(name, t)
  local dir = ensureLayoutsDir()
  local path = dir .. "/" .. name .. ".lua"
  local f, err = io.open(path, "w")
  if not f then
    hs.alert.show("Write failed: " .. tostring(err))
    return false
  end
  f:write(layoutToLua(t))
  f:close()
  return true
end

function M.upsertFocusedWindowToLayout(name)
  if name == nil or name == "" or name == "AUTO" then
    name = M.suggestLayoutName()
    hs.alert.show("Upsert → " .. name)
  end
  local cap = captureFocused()
  if not cap or not cap.windows or not cap.windows[1] then
    hs.alert.show("No focused standard window")
    return
  end
  local item = cap.windows[1]
  local t = loadLayoutTable(name)
  local previousByKey = {}
  for _, existing in ipairs(t.windows or {}) do
    previousByKey[layoutWindowKey(existing)] = existing
  end
  item = stabilizeCapturedItem(item, previousByKey)
  if not item then
    hs.alert.show("Failed to capture focused window")
    return
  end

  local replaced = false
  for i, it in ipairs(t.windows) do
    if it.bundleID == item.bundleID and it.windowIndex == item.windowIndex then
      t.windows[i] = item
      replaced = true
      break
    end
  end
  if not replaced then table.insert(t.windows, item) end

  t.signature = screenSignature()

  if writeLayoutTable(name, t) then
    hs.alert.show((replaced and "Updated: " or "Added: ") .. name)
  end
end



-- ===== Layout state (lastAppliedAt) — git管理外の別ファイルに保存 =====
-- レイアウトファイル自体は純粋な定義のみ。実行時状態はここに分離。
-- ファイルが存在しない場合（git clone直後など）は自動作成される。

local LAYOUT_STATE_FILE = (os.getenv("HOME") or "") .. "/.hammerspoon/layout_state.json"

local function loadLayoutState()
  local f = io.open(LAYOUT_STATE_FILE, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return {} end
  local ok, state = pcall(hs.json.decode, content)
  if not ok or type(state) ~= "table" then return {} end
  return state
end

local function saveLayoutState(state)
  local ok, content = pcall(hs.json.encode, state)
  if not ok then
    hs.printf("wm: failed to encode layout state")
    return false
  end
  local f = io.open(LAYOUT_STATE_FILE, "w")
  if not f then
    hs.printf("wm: failed to write layout state: %s", LAYOUT_STATE_FILE)
    return false
  end
  f:write(content)
  f:close()
  return true
end

local function touchLayoutState(id)
  if not id then return end
  local state = loadLayoutState()
  state[tostring(id)] = os.time()
  saveLayoutState(state)
end

-- ===== Numbered layouts (001__monitors__title.lua) =====

local function normalizeLayoutId(id)
  if id == nil then return nil end
  local s = tostring(id):match("^%s*(.-)%s*$")
  if not s:match("^%d+$") then return nil end
  local n = tonumber(s)
  if not n or n < 1 or n > 999 then return nil end
  return string.format("%03d", n)
end

local function listLayoutFiles()
  local dir = ensureLayoutsDir()
  local files = {}
  for file in fs.dir(dir) do
    if file ~= "." and file ~= ".." and file:sub(-4) == ".lua" then
      table.insert(files, file)
    end
  end
  table.sort(files)
  return dir, files
end

local function findLayoutPathById(id)
  local norm = normalizeLayoutId(id)
  if not norm then return nil, "Invalid id" end

  local dir, files = listLayoutFiles()
  local matches = {}
  for _, file in ipairs(files) do
    if file:match("^" .. norm .. "__.+%.lua$") then
      table.insert(matches, dir .. "/" .. file)
    end
  end

  if #matches == 0 then return nil, "Not found: " .. norm end
  if #matches > 1 then return nil, "Multiple files found for id: " .. norm end
  return matches[1], nil
end

local function nextAvailableLayoutId()
  local _, files = listLayoutFiles()
  local used = {}
  for _, file in ipairs(files) do
    local id = file:match("^(%d%d%d)__")
    if id then used[tonumber(id)] = true end
  end
  for n = 1, 999 do
    if not used[n] then return string.format("%03d", n) end
  end
  return nil
end

local function asciiSlug(s)
  local out = tostring(s or "")
  out = out:lower()
  out = out:gsub("%s+", "")
  out = out:gsub("[^%w]+", "")
  if out == "" then out = "display" end
  return out
end

local function monitorTagForScreen(s)
  local name = (s:name() or ""):lower()
  local patterns = { "built%-in", "color lcd", "内蔵", "ビルトイン", "retina" }
  for _, p in ipairs(patterns) do
    if name:find(p) then return "macbook" end
  end
  return asciiSlug(s:name() or "display")
end

local function currentMonitorsTag()
  local screens = screen.allScreens()
  local primary = screen.primaryScreen()
  local primaryUUID = primary and primary:getUUID() or nil

  local primaryTag = nil
  local others = {}

  for _, s in ipairs(screens) do
    local tag = monitorTagForScreen(s)
    if primaryUUID and s:getUUID() == primaryUUID then
      primaryTag = tag
    else
      table.insert(others, tag)
    end
  end

  table.sort(others)

  local tags = {}
  local seen = {}

  if primaryTag and not seen[primaryTag] then
    table.insert(tags, primaryTag)
    seen[primaryTag] = true
  end

  for _, tag in ipairs(others) do
    if not seen[tag] then
      table.insert(tags, tag)
      seen[tag] = true
    end
  end

  return table.concat(tags, "+")
end

local function sanitizeTitleForFilename(title)
  local s = tostring(title or "")
  s = s:match("^%s*(.-)%s*$")
  s = s:gsub("[%c]", "")
  s = s:gsub("[%z/:]", "")
  s = s:gsub("%s+", "-")
  s = s:gsub("__+", "_")
  if s == "" then s = "untitled" end
  if #s > 60 then s = s:sub(1, 60) end
  return s
end

local function numberedLayoutFilename(id, monitors, title)
  local monitorsPart = tostring(monitors or "")
  if monitorsPart == "" then monitorsPart = "monitors" end

  local titlePart = sanitizeTitleForFilename(title)
  return string.format("%s__%s__%s.lua", id, monitorsPart, titlePart)
end

local function loadLayoutByPath(path)
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, layout = pcall(chunk)
  if not ok then return nil, layout end
  if type(layout) ~= "table" then return nil, "Layout did not return a table" end
  layout.windows = layout.windows or {}
  return layout, nil
end

local function layoutToLuaNumbered(layout)
  local lines = {}

  local title = tostring(layout.title or "")
  local desc = tostring(layout.description or "")

  table.insert(lines, "-- title: " .. title)
  table.insert(lines, "-- description:")
  if desc == "" then
    table.insert(lines, "--   (write here)")
  else
    for line in desc:gmatch("[^\n]+") do
      table.insert(lines, "--   " .. line)
    end
  end
  table.insert(lines, "")

  table.insert(lines, "return {")
  table.insert(lines, string.format('  id = %q,', layout.id))
  table.insert(lines, string.format('  title = %q,', title))
  table.insert(lines, string.format('  monitors = %q,', tostring(layout.monitors or "")))
  table.insert(lines, string.format('  signature = %q,', tostring(layout.signature or "")))
  table.insert(lines, string.format('  createdAt = %d,', tonumber(layout.createdAt or 0)))
  table.insert(lines, string.format('  updatedAt = %d,', tonumber(layout.updatedAt or 0)))
  table.insert(lines, string.format('  description = %q,', desc))

  table.insert(lines, "  windows = {")
  for _, it in ipairs(layout.windows or {}) do
    table.insert(lines,
      string.format(
        '    { bundleID=%q, windowIndex=%d, screenUUID=%q, unit={x=%.4f,y=%.4f,w=%.4f,h=%.4f} },',
        it.bundleID, it.windowIndex, it.screenUUID,
        it.unit.x, it.unit.y, it.unit.w, it.unit.h
      )
    )
  end
  table.insert(lines, "  }")
  table.insert(lines, "}")
  return table.concat(lines, "\n")
end

local function writeLayoutByPath(path, layout)
  local f, err = io.open(path, "w")
  if not f then return false, err end
  f:write(layoutToLuaNumbered(layout))
  f:close()
  return true, nil
end

local function signatureMismatchMessage(layout)
  return "Signature mismatch (current != layout). Are you on the correct display setup?"
end

function M.layoutNew(title, description)
  local now = os.time()
  local id = nextAvailableLayoutId()
  if not id then
    hs.alert.show("No available id")
    return
  end

  local monitors = currentMonitorsTag()
  local filename = numberedLayoutFilename(id, monitors, title)
  local dir = ensureLayoutsDir()
  local path = dir .. "/" .. filename

  local cap = captureAll()

  local titleStr = tostring(title or "")
  if titleStr == "" then titleStr = "untitled" end

  local layout = {
    id = id,
    title = titleStr,
    description = tostring(description or ""),
    monitors = monitors,
    signature = cap.signature,
    createdAt = now,
    updatedAt = now,
    windows = cap.windows,
  }

  local ok, err = writeLayoutByPath(path, layout)
  if not ok then
    hs.alert.show("Create failed: " .. tostring(err))
    return
  end

  hs.alert.show("Created: " .. id)
end

function M.layoutUpdate(id)
  local path, err = findLayoutPathById(id)
  if not path then
    hs.alert.show(tostring(err))
    return
  end

  local layout, lerr = loadLayoutByPath(path)
  if not layout then
    hs.alert.show("Load failed: " .. tostring(lerr))
    return
  end

  local currentSig = screenSignature()
  if tostring(layout.signature or "") ~= tostring(currentSig) then
    hs.alert.show(signatureMismatchMessage(layout))
    return
  end

  local cap = captureAll()
  layout.windows = stabilizeCapturedWindows(cap.windows, layout.windows)
  layout.updatedAt = os.time()

  local ok, werr = writeLayoutByPath(path, layout)
  if not ok then
    hs.alert.show("Update failed: " .. tostring(werr))
    return
  end

  hs.alert.show("Updated: " .. tostring(layout.id or ""))
end

function M.layoutUpsertActive(id)
  local path, err = findLayoutPathById(id)
  if not path then
    hs.alert.show(tostring(err))
    return
  end

  local layout, lerr = loadLayoutByPath(path)
  if not layout then
    hs.alert.show("Load failed: " .. tostring(lerr))
    return
  end

  local currentSig = screenSignature()
  if tostring(layout.signature or "") ~= tostring(currentSig) then
    hs.alert.show(signatureMismatchMessage(layout))
    return
  end

  local cap = captureFocused()
  if not cap or not cap.windows or not cap.windows[1] then
    hs.alert.show("No focused standard window")
    return
  end

  local item = cap.windows[1]
  layout.windows = layout.windows or {}
  local previousByKey = {}
  for _, existing in ipairs(layout.windows) do
    previousByKey[layoutWindowKey(existing)] = existing
  end
  item = stabilizeCapturedItem(item, previousByKey)
  if not item then
    hs.alert.show("Failed to capture focused window")
    return
  end

  local replaced = false
  for i, it in ipairs(layout.windows) do
    if it.bundleID == item.bundleID and it.windowIndex == item.windowIndex then
      layout.windows[i] = item
      replaced = true
      break
    end
  end
  if not replaced then table.insert(layout.windows, item) end

  layout.updatedAt = os.time()

  local ok, werr = writeLayoutByPath(path, layout)
  if not ok then
    hs.alert.show("Upsert failed: " .. tostring(werr))
    return
  end

  hs.alert.show((replaced and "Updated: " or "Added: ") .. tostring(layout.id or ""))
end

function M.layoutApply(id, opts)
  local silent = opts and opts.silent

  local path, err = findLayoutPathById(id)
  if not path then
    if not silent then hs.alert.show(tostring(err)) end
    return false
  end

  local layout, lerr = loadLayoutByPath(path)
  if not layout then
    if not silent then hs.alert.show("Load failed: " .. tostring(lerr)) end
    return false
  end

  local force = opts and opts.force
  local currentSig = screenSignature()
  local signatureMatched = tostring(layout.signature or "") == tostring(currentSig)
  if (not force) and (not signatureMatched) then
    if not silent then hs.alert.show(signatureMismatchMessage(layout)) end
    return false
  end

  applyLayout(layout)

  -- normalize unit rects to avoid future 'not a unit rect' crashes
  for _, it in ipairs(layout.windows or {}) do
    local unit = sanitizeUnitRect(it.unit)
    if unit then it.unit = unit end
  end

  -- Avoid skewing auto-pick ordering when a manual force apply is done on mismatched displays.
  if signatureMatched or (not force) then
    touchLayoutState(layout.id)
  end
  local ok, werr = writeLayoutByPath(path, layout)
  if not ok then
    if not silent then hs.alert.show("Apply ok, but failed to update metadata: " .. tostring(werr)) end
    return false
  end

  lastAppliedSignature = currentSig
  if not silent then hs.alert.show("Applied: " .. tostring(layout.id or "")) end
  return true
end

function M.layoutRename(id, title, description)
  local path, err = findLayoutPathById(id)
  if not path then
    hs.alert.show(tostring(err))
    return
  end

  local layout, lerr = loadLayoutByPath(path)
  if not layout then
    hs.alert.show("Load failed: " .. tostring(lerr))
    return
  end

  layout.title = tostring(title or layout.title or "")
  if description ~= nil then
    layout.description = tostring(description)
  end
  layout.updatedAt = os.time()

  local monitors = tostring(layout.monitors or "")
  if monitors == "" then monitors = currentMonitorsTag() end

  local newFilename = numberedLayoutFilename(tostring(layout.id or normalizeLayoutId(id) or ""), monitors, layout.title)
  local dir = ensureLayoutsDir()
  local newPath = dir .. "/" .. newFilename

  local ok, werr = writeLayoutByPath(newPath, layout)
  if not ok then
    hs.alert.show("Rename failed: " .. tostring(werr))
    return
  end

  if newPath ~= path then
    os.remove(path)
  end

  hs.alert.show("Renamed: " .. tostring(layout.id or ""))
end

function M.layoutApplyAuto(opts)
  local currentSig = screenSignature()
  local dir, files = listLayoutFiles()

  local state = loadLayoutState()
  local candidates = {}
  for _, file in ipairs(files) do
    local id = file:match("^(%d%d%d)__")
    if id then
      local path = dir .. "/" .. file
      local layout = loadLayoutByPath(path)
      if layout and tostring(layout.signature or "") == tostring(currentSig) then
        local layoutId = tostring(layout.id or id)
        table.insert(candidates, {
          id = layoutId,
          path = path,
          lastAppliedAt = state[layoutId] or 0,
        })
      end
    end
  end

  if #candidates == 0 then
    return false
  end

  table.sort(candidates, function(a, b)
    if a.lastAppliedAt ~= b.lastAppliedAt then
      return a.lastAppliedAt > b.lastAppliedAt
    end
    return tonumber(a.id) < tonumber(b.id)
  end)

  local best = candidates[1]
  local silent = opts and opts.silent

  return M.layoutApply(best.id, { force = false, silent = silent })
end

function M.applyAutoLayoutIfNeeded()
  local currentSig = screenSignature()
  if lastAppliedSignature == currentSig then return end

  local ok = M.layoutApplyAuto({ silent = false })
  if ok then
    lastAppliedSignature = currentSig
  end
end

function M.startAutoWatchers()
  lastAppliedSignature = nil

  if M._screenWatcherAuto then M._screenWatcherAuto:stop() end
  if M._wakeWatcherAuto then M._wakeWatcherAuto:stop() end

  M._screenWatcherAuto = hs.screen.watcher.new(function()
    M.applyAutoLayoutIfNeeded()
  end):start()

  M._wakeWatcherAuto = caffeinateWatcher.new(function(ev)
    if ev == caffeinateWatcher.screensDidWake or ev == caffeinateWatcher.systemDidWake then
      M.applyAutoLayoutIfNeeded()
    end
  end):start()
end

return M
