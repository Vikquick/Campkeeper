local _, ns = ...
local L = ns.L
local Util = ns.Util

-- Camp panel next to the buffs. Shown while NEAR/SITTING/BUFFED, hidden 10 s after AWAY and
-- always hidden in combat. Rows that can be placed are secure item buttons; their attributes
-- (and the panel's visibility, since it parents them) change only out of combat.
local Panel = { MAX_ROWS = 14, ROW_HEIGHT = 18, WIDTH = 260, HIDE_DELAY = 10, HINT_TIME = 6 }
ns.Panel = Panel

local STATUS_TEXT = { placed = "placed", placeable = "click to place", covered = "covered by a class buff" }
local STATUS_COLOR = { placed = { 0.3, 1, 0.3 }, placeable = { 1, 0.82, 0 }, covered = { 0.6, 0.6, 0.6 } }

local frame, rows, title, cooldownText, bar, barText, hint
local pendingUpdate, hideTimer, hintTimer = false, nil, nil

local function inCombat() return InCombatLockdown() end

local function profile() return ns.db.profile.panel end

local function savePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  profile().point = { point, relPoint, x, y }
end

local function createRow(i)
  local b = CreateFrame("Button", "CampkeeperPanelRow" .. i, frame, "SecureActionButtonTemplate")
  b:SetHeight(Panel.ROW_HEIGHT)
  b:SetPoint("LEFT", frame, "LEFT", 8, 0)
  b:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(16, 16)
  b.icon:SetPoint("LEFT")
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.name:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b.name:SetJustifyH("LEFT")
  b.status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.status:SetPoint("RIGHT")
  b.status:SetJustifyH("RIGHT")
  b:SetScript("PreClick", function(self) if self.key then ns.OwnCamp:NoteAttempt(self.key) end end)
  b:SetScript("OnEnter", function(self)
    if not self.key then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    if self.item then
      GameTooltip:SetItemByID(self.item)
    else
      GameTooltip:AddLine(ns.Catalog:Name(self.key))
      local desc = ns.Catalog:Description(self.key)
      if desc then GameTooltip:AddLine(desc, 1, 1, 1, true) end
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
  return b
end

local function create()
  frame = CreateFrame("Frame", "CampkeeperPanel", UIParent, "BackdropTemplate")
  frame:SetSize(Panel.WIDTH, 80)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0, 0, 0, 0.75)
  end
  local p = profile().point
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -210) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() and not inCombat() then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition() end)

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 8, -8)
  title:SetPoint("TOPRIGHT", -8, -8)
  title:SetJustifyH("LEFT")

  cooldownText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cooldownText:SetJustifyH("LEFT")

  bar = CreateFrame("StatusBar", nil, frame)
  bar:SetHeight(14)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(1, 0.55, 0.1)
  bar:SetMinMaxValues(0, 1)
  barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  barText:SetPoint("CENTER")

  hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetTextColor(1, 0.3, 0.3)
  hint:SetJustifyH("LEFT")

  rows = {}
  for i = 1, Panel.MAX_ROWS do rows[i] = createRow(i) end
  Panel.rows, Panel.frame, Panel.title, Panel.bar, Panel.barText, Panel.hint, Panel.cooldownText =
    rows, frame, title, bar, barText, hint, cooldownText
  frame:Hide()
end

local function headerText(h)
  local parts = {}
  if h.fireTier then
    parts[1] = ns.Catalog:Name("fire" .. h.fireTier)
    if h.slots then parts[#parts + 1] = ("%d/%d"):format(h.used, h.slots) end
    if h.fireRemaining then parts[#parts + 1] = L["goes out in %s"]:format(Util.formatDuration(h.fireRemaining)) end
  else
    parts[1] = L["Camp"]
  end
  return table.concat(parts, " · ")
end

local function sittingText(s)
  if s.state == "SITTING" and s.remaining then
    return L["Stay seated: %d s"]:format(math.ceil(s.remaining)), 1 - s.remaining / 60
  elseif s.state == "BUFFED" and s.benefitsRemaining then
    return L["Benefits until %s"]:format(date("%H:%M", ns.api.serverTime() + s.benefitsRemaining)), 1
  end
  return L["Sit by the fire to get the camp benefits"], 0
end

-- Secure parts (row attributes, row and panel visibility) — out of combat only.
local function applySecure(model)
  for i, b in ipairs(rows) do
    local r = model and model.rows[i]
    if r then
      b.key, b.item = r.key, (r.status == "placeable") and r.item or nil
      b:SetAttribute("type", b.item and "item" or nil)
      b:SetAttribute("item", b.item and ("item:" .. b.item) or nil)
      b:Show()
    else
      b.key, b.item = nil, nil
      b:SetAttribute("type", nil)
      b:SetAttribute("item", nil)
      b:Hide()
    end
  end
end

-- Text, icons, layout — safe in any state.
local function render(model)
  title:SetText(headerText(model.header))
  local y = -26
  if model.header.cooldownRemaining and model.header.cooldownRemaining > 0 then
    cooldownText:SetText(L["Camping cooldown: %s"]:format(Util.formatDuration(model.header.cooldownRemaining)))
    cooldownText:ClearAllPoints()
    cooldownText:SetPoint("TOPLEFT", 8, y)
    cooldownText:Show()
    y = y - 14
  else
    cooldownText:Hide()
  end
  for i, b in ipairs(rows) do
    local r = model.rows[i]
    if r then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y)
      b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, y)
      b.icon:SetTexture(ns.Catalog:Icon(r.key))
      b.name:SetText(ns.Catalog:Name(r.key))
      b.status:SetText(r.status == "placed" and r.effect or L[STATUS_TEXT[r.status]])
      b.status:SetTextColor(unpack(STATUS_COLOR[r.status]))
      y = y - Panel.ROW_HEIGHT
    end
  end
  local text, value = sittingText(model.sitting)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, y - 4)
  bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, y - 4)
  bar:SetValue(value)
  barText:SetText(text)
  y = y - 22
  if hint:GetText() then
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", 8, y)
    y = y - 14
  end
  frame:SetHeight(-y + 8)
end

local function wanted()
  if not profile().enabled or inCombat() then return false end
  return ns.CampState:Get() ~= "AWAY" or hideTimer ~= nil
end

function Panel:Update()
  if not frame then return end
  -- rows are secure: no layout, attribute or visibility change while in combat (panel is hidden)
  if inCombat() then pendingUpdate = true; return end
  pendingUpdate = false
  local model = ns.PanelModel:Build()
  self.model = model
  render(model)
  applySecure(model)
  if wanted() then frame:Show() else frame:Hide() end
end

function Panel:ShowHint(text)
  hint:SetText(text)
  if hintTimer then hintTimer:Cancel() end
  hintTimer = ns.api.timer(self.HINT_TIME, function() hintTimer = nil; hint:SetText(nil); Panel:Update() end)
  self:Update()
end

function Panel:IsShown() return frame and frame:IsShown() end

function Panel:Init()
  create()
  local function update() Panel:Update() end
  for _, event in ipairs({ "CAMP_BENEFITS_PARSED", "OWN_CAMP_PLACED", "OWN_CAMP_UPDATED", "PROFESSIONS_UPDATED",
                           "CAMP_COOLDOWN_UPDATED", "CATALOG_UPDATED", "SETTINGS_CHANGED" }) do
    ns.RegisterCallback(self, event, update)
  end
  ns.RegisterCallback(self, "CAMP_STATE_CHANGED", function(_, _, new)
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    if new == "AWAY" and frame:IsShown() then
      hideTimer = ns.api.timer(self.HIDE_DELAY, function() hideTimer = nil; Panel:Update() end)
    end
    Panel:Update()
  end)
  ns.RegisterCallback(self, "CAMP_PLACE_FAILED", function(_, _, reason)
    if reason == "cooldown" then
      self:ShowHint(L["Camping items are on cooldown: %s"]:format(Util.formatDuration(ns.OwnCamp:CooldownRemaining() or 0)))
    else
      self:ShowHint(L["Too close to another object or creature."])
    end
  end)

  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
      frame:Hide() -- still allowed here: lockdown begins after this event
    elseif pendingUpdate or wanted() then
      Panel:Update()
    end
  end)
  -- timers on the panel tick once a second while it is shown
  self.ticker = C_Timer.NewTicker(1, function() if frame:IsShown() then Panel:Update() end end)
  self:Update()
end
