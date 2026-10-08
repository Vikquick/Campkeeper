local _, ns = ...
local L = ns.L

-- Planner tab: group members with professions (own data, PROF messages from their Campkeeper,
-- or entered by hand), fire tier and role -> plan, and a button that posts it to group chat.
local PlannerTab = { PROF_DELAY = 3, MAX_PLAN_LINES = 12, MAX_MEMBERS = 8 }
ns.PlannerTab = PlannerTab

local ROLE_LABEL = { leveling = "Leveling", dungeon = "Dungeon", craft = "Crafting" }
local received, manual = {}, {} -- [name] = { [professionKey] = skill }
local state = { role = "leveling", fireTier = 1, member = 1, profession = 1 }
local ui = {}

local function professionKeys()
  local keys = {}
  for key in pairs(ns.CatalogData.professions) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local skillLineToKey
local function keyForSkillLine(id)
  if not skillLineToKey then
    skillLineToKey = {}
    for key, line in pairs(ns.CatalogData.professions) do skillLineToKey[line] = key end
  end
  return skillLineToKey[id]
end

-- PROF payload from a group member: { [skillLineID] = skill } -> store by profession key.
function PlannerTab:OnProfessions(name, payload)
  local profs = {}
  for line, skill in pairs(payload) do
    local key = type(line) == "number" and keyForSkillLine(line)
    if key and type(skill) == "number" and skill >= 0 and skill <= 450 then profs[key] = math.floor(skill) end
  end
  received[name] = profs
  if ns.Window:IsShown() then self:Refresh() end
end

function PlannerTab:SetManual(name, professionKey, skill)
  manual[name] = manual[name] or {}
  manual[name][professionKey] = skill
end

local function groupUnits()
  local units = { "player" }
  if IsInRaid() then
    units = {}
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  elseif IsInGroup() then
    for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
  end
  return units
end

-- Planner input members: { name, class, professions, source = "self"|"addon"|"manual"|"none" }.
function PlannerTab:Members()
  local me = UnitName("player")
  local out = {}
  for _, unit in ipairs(groupUnits()) do
    local name = UnitName(unit)
    if name then
      local _, class = UnitClass(unit)
      local profs, source = {}, "none"
      if name == me then
        for key, p in pairs(ns.Professions:Char().professions) do profs[key] = p.skill end
        source = "self"
      elseif received[name] then
        profs, source = received[name], "addon"
      end
      for key, skill in pairs(manual[name] or {}) do profs[key] = skill; if source == "none" then source = "manual" end end
      out[#out + 1] = { name = name, class = class, professions = profs, source = source }
    end
  end
  return out
end

function PlannerTab:Plan()
  return ns.Planner:Plan({ members = self:Members(), fireTier = state.fireTier, role = state.role })
end

-- Own professions to the group (PROF message).
function PlannerTab:SendProfessions()
  if not IsInGroup() then return end
  local payload = {}
  for key, p in pairs(ns.Professions:Char().professions) do payload[ns.CatalogData.professions[key]] = p.skill end
  ns.Comm:Send({ v = ns.Protocol.VERSION, t = "PROF", p = payload }, IsInRaid() and "RAID" or "PARTY")
end

function PlannerTab:PostToChat()
  local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
  for _, line in ipairs(ns.Planner:ChatLines(self:Plan())) do
    if channel then SendChatMessage(line, channel) else ns.addon:Print(line) end
  end
end

-- UI ---------------------------------------------------------------------------------------

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

function PlannerTab:Create(parent)
  local x = 0
  ui.roles = {}
  for _, role in ipairs(ns.Planner.ROLES) do
    local b = button(parent, L[ROLE_LABEL[role]], 110, function() state.role = role; PlannerTab:Refresh() end)
    b:SetPoint("TOPLEFT", x, 0)
    ui.roles[role] = b
    x = x + 114
  end
  x = x + 20
  ui.fires = {}
  for tier = 1, 3 do
    local b = button(parent, L["%d slots"]:format(ns.Catalog:Fire(tier).slots), 80,
      function() state.fireTier = tier; PlannerTab:Refresh() end)
    b:SetPoint("TOPLEFT", x, 0)
    ui.fires[tier] = b
    x = x + 84
  end

  ui.members = {}
  for i = 1, self.MAX_MEMBERS do
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 0, -34 - (i - 1) * 16)
    fs:SetWidth(320)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    ui.members[i] = fs
  end

  -- manual entry: member < > , profession < >, skill, Add
  local y = -34 - self.MAX_MEMBERS * 16 - 8
  ui.memberButton = button(parent, "", 150, function()
    local n = #PlannerTab:Members()
    state.member = n > 0 and (state.member % n) + 1 or 1
    PlannerTab:Refresh()
  end)
  ui.memberButton:SetPoint("TOPLEFT", 0, y)
  ui.professionButton = button(parent, "", 150, function()
    state.profession = (state.profession % #professionKeys()) + 1
    PlannerTab:Refresh()
  end)
  ui.professionButton:SetPoint("LEFT", ui.memberButton, "RIGHT", 4, 0)
  ui.skill = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  ui.skill:SetSize(50, 22)
  ui.skill:SetAutoFocus(false)
  ui.skill:SetNumeric(true)
  ui.skill:SetMaxLetters(3)
  ui.skill:SetPoint("LEFT", ui.professionButton, "RIGHT", 10, 0)
  ui.add = button(parent, L["Add"], 80, function()
    local member = PlannerTab:Members()[state.member]
    local skill = tonumber(ui.skill:GetText())
    if member and skill then
      PlannerTab:SetManual(member.name, professionKeys()[state.profession], math.min(skill, 450))
      ui.skill:SetText("")
      ui.skill:ClearFocus()
      PlannerTab:Refresh()
    end
  end)
  ui.add:SetPoint("LEFT", ui.skill, "RIGHT", 4, 0)

  ui.planTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.planTitle:SetPoint("TOPLEFT", 350, -34)
  ui.planTitle:SetText(L["Plan"])
  ui.plan = {}
  for i = 1, self.MAX_PLAN_LINES do
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 350, -52 - (i - 1) * 16)
    fs:SetWidth(320)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    ui.plan[i] = fs
  end
  ui.post = button(parent, L["To group chat"], 160, function() PlannerTab:PostToChat() end)
  ui.post:SetPoint("BOTTOMRIGHT", 0, 0)
end

local SOURCE = { self = "you", addon = "via Campkeeper", manual = "entered by hand", none = "no data" }

function PlannerTab:Refresh()
  if not ui.members then return end
  for role, b in pairs(ui.roles) do b:SetEnabled(role ~= state.role) end
  for tier, b in pairs(ui.fires) do b:SetEnabled(tier ~= state.fireTier) end

  local members = self:Members()
  for i, fs in ipairs(ui.members) do
    local m = members[i]
    if m then
      local profs = {}
      for key, skill in pairs(m.professions) do
        profs[#profs + 1] = ("%s %d"):format(L[ns.CatalogTab.PROFESSION_NAMES[key]], skill)
      end
      table.sort(profs)
      fs:SetText(("%s (%s): %s"):format(m.name, L[SOURCE[m.source]], #profs > 0 and table.concat(profs, ", ") or "-"))
    else
      fs:SetText(nil)
    end
  end
  if state.member > #members then state.member = 1 end
  ui.memberButton:SetText(members[state.member] and members[state.member].name or "-")
  local prof = professionKeys()[state.profession]
  ui.professionButton:SetText(L[ns.CatalogTab.PROFESSION_NAMES[prof]])

  local plan = self:Plan()
  local lines = {}
  if plan.fire then
    lines[#lines + 1] = ("%s - %s"):format(ns.Catalog:Name("fire" .. plan.fire.tier), plan.fire.member)
  else
    lines[#lines + 1] = L["Nobody can light this fire (Cooking %d)"]:format(ns.Catalog:Fire(state.fireTier).skill)
  end
  for _, o in ipairs(plan.objects) do
    lines[#lines + 1] = ("%s (T%d) - %s"):format(ns.Catalog:Name(o.key), o.tier, o.member)
  end
  for i, fs in ipairs(ui.plan) do fs:SetText(lines[i]) end
  self.lastPlan = plan
end

function PlannerTab:Init()
  ns.RegisterCallback(self, "GROUP_PROFESSIONS", function(_, name, payload) PlannerTab:OnProfessions(name, payload) end)
  local pending
  local events = CreateFrame("Frame")
  events:RegisterEvent("GROUP_ROSTER_UPDATE")
  events:SetScript("OnEvent", function()
    if pending then pending:Cancel() end
    pending = ns.api.timer(PlannerTab.PROF_DELAY, function() pending = nil; PlannerTab:SendProfessions() end)
  end)
end
