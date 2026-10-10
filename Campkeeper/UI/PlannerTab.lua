local _, ns = ...
local L = ns.L

-- Planner tab: group members with professions (own data and PROF messages from their Campkeeper;
-- members without the addon are listed but not planned), fire tier and role -> plan, and a button
-- that posts it to group chat.
local PlannerTab = { PROF_DELAY = 3, MAX_PLAN_LINES = 12, MAX_MEMBERS = 10 }
ns.PlannerTab = PlannerTab

local ROLE_LABEL = { leveling = "Leveling", dungeon = "Dungeon", craft = "Crafting" }
local received = {} -- [name] = { [professionKey] = skill } from PROF messages
local state = { role = "leveling", fireTier = 1 }
local ui = {}

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

-- Group members: { name, class, professions, source = "self"|"addon"|"none" }.
function PlannerTab:Members()
  local me = ns.api.unitFullName("player")
  local out = {}
  for _, unit in ipairs(groupUnits()) do
    local name = ns.api.unitFullName(unit)
    if name then
      local _, class = UnitClass(unit)
      local profs, source = {}, "none"
      if name == me then
        for key, p in pairs(ns.Professions:Char().professions) do profs[key] = p.skill end
        source = "self"
      elseif received[name] then
        for key, skill in pairs(received[name]) do profs[key] = skill end
        source = "addon"
      end
      out[#out + 1] = { name = name, class = class, professions = profs, source = source }
    end
  end
  return out
end

function PlannerTab:Plan()
  -- everyone counts for class buffs; members without Campkeeper have no professions, so they get nothing
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

-- Explanations under the plan: why it is shorter than the number of places.
function PlannerTab:Notes(plan)
  local notes = {}
  if not plan.fire then
    notes[#notes + 1] = L["Nobody can light this fire (Cooking %d)"]:format(ns.Catalog:Fire(state.fireTier).skill)
  end
  local members = self:Members()
  local known = 0
  for _, m in ipairs(members) do if m.source ~= "none" then known = known + 1 end end
  if #plan.objects < plan.slots then
    if #members <= 1 then
      notes[#notes + 1] = L["You are alone: other objects need more group members."]
    else
      local used = #plan.objects + (plan.fire and 1 or 0)
      if used >= known then
        notes[#notes + 1] = L["Every member already places something; more members would fill the free places."]
      else
        notes[#notes + 1] = L["The remaining members have no profession skill for the other objects."]
      end
    end
  end
  local unknown = {}
  for _, m in ipairs(members) do if m.source == "none" then unknown[#unknown + 1] = m.name end end
  if #unknown > 0 then
    notes[#notes + 1] = L["Without Campkeeper: %s - their professions are unknown and not planned."]:format(table.concat(unknown, ", "))
  end
  if #plan.covered > 0 then
    local names = {}
    for _, key in ipairs(plan.covered) do names[#names + 1] = ns.Catalog:Name(key) end
    notes[#notes + 1] = L["Skipped, a class in the group gives this buff: %s"]:format(table.concat(names, ", "))
  end
  return notes
end

-- Numbered plan lines.
function PlannerTab:PlanLines(plan)
  local lines = {}
  if plan.fire then
    lines[#lines + 1] = ("%d. %s - %s"):format(#lines + 1, ns.Catalog:Name("fire" .. plan.fire.tier), plan.fire.member)
  end
  for _, o in ipairs(plan.objects) do
    lines[#lines + 1] = ("%d. %s (T%d) - %s"):format(#lines + 1, ns.Catalog:Name(o.key), o.tier, o.member)
  end
  return lines
end

-- UI ---------------------------------------------------------------------------------------

local ROW = 30          -- member row height (name + professions)
local RIGHT = 400       -- x of the plan column

local function label(parent, text, font, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  if width then fs:SetWidth(width) end
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

-- Radio group: { { value, text } }, current value from get(), set(value) on click.
local function radios(parent, x, y, options, get, set)
  local group = {}
  for _, opt in ipairs(options) do
    local r = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    r:SetPoint("TOPLEFT", x, y)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", r, "RIGHT", 2, 0)
    r.label:SetText(opt[2])
    r.value = opt[1]
    r:SetScript("OnClick", function() set(opt[1]); PlannerTab:Refresh() end)
    group[#group + 1] = r
    x = x + 34 + math.max(60, r.label:GetStringWidth() or 0)
  end
  group.sync = function()
    for _, r in ipairs(group) do r:SetChecked(r.value == get()) end
  end
  return group
end

local SOURCE = { self = "you", addon = "via Campkeeper", none = "no Campkeeper" }

function PlannerTab:Create(parent)
  label(parent, L["Who places what in the group camp"], "GameFontNormalLarge", 0, 0)
  label(parent, L["Each member places one camping item now; the next one only after the shared cooldown."], "GameFontHighlightSmall", 0, -20, 660)

  label(parent, L["Goal:"], "GameFontNormal", 0, -46)
  local roleOptions = {}
  for _, role in ipairs(ns.Planner.ROLES) do roleOptions[#roleOptions + 1] = { role, L[ROLE_LABEL[role]] } end
  ui.roles = radios(parent, 70, -42, roleOptions, function() return state.role end, function(v) state.role = v end)

  label(parent, L["Campfire:"], "GameFontNormal", 0, -72)
  local fireOptions = {}
  for tier = 1, 3 do
    fireOptions[tier] = { tier, L["%s, %d places"]:format(ns.Catalog:Name("fire" .. tier), ns.Catalog:Fire(tier).slots) }
  end
  ui.fires = radios(parent, 70, -68, fireOptions, function() return state.fireTier end, function(v) state.fireTier = v end)

  label(parent, L["Members"], "GameFontNormal", 0, -102)
  ui.members = {}
  for i = 1, self.MAX_MEMBERS do
    local y = -120 - (i - 1) * ROW
    local row = {
      name = label(parent, "", "GameFontHighlight", 0, y, 240),
      profs = label(parent, "", "GameFontDisableSmall", 12, y - 14, RIGHT - 24),
    }
    row.name:SetWordWrap(false)
    row.profs:SetWordWrap(false)
    ui.members[i] = row
  end

  label(parent, L["Plan"], "GameFontNormal", RIGHT, -102)
  ui.plan = {}
  for i = 1, self.MAX_PLAN_LINES do
    ui.plan[i] = label(parent, "", "GameFontHighlight", RIGHT, -120 - (i - 1) * 16, 270)
    ui.plan[i]:SetWordWrap(false)
  end
  ui.notes = label(parent, "", "GameFontDisableSmall", RIGHT, -120 - self.MAX_PLAN_LINES * 16 - 6, 270)
  ui.post = button(parent, L["Post the plan to group chat"], 220, function() PlannerTab:PostToChat() end)
  ui.post:SetPoint("BOTTOMRIGHT", 0, 0)
  self.ui = ui
end

function PlannerTab:Refresh()
  if not ui.members then return end
  ui.roles.sync()
  ui.fires.sync()

  local members = self:Members()
  for i, row in ipairs(ui.members) do
    local m = members[i]
    if m then
      local profs = {}
      for key, skill in pairs(m.professions) do
        profs[#profs + 1] = ("%s %d"):format(L[ns.CatalogTab.PROFESSION_NAMES[key]], skill)
      end
      table.sort(profs)
      row.memberName = m.name
      row.name:SetText(("%s (%s)"):format(m.name, L[SOURCE[m.source]]))
      row.profs:SetText(#profs > 0 and table.concat(profs, ", ") or L["no professions known"])
      row.name:Show()
      row.profs:Show()
    else
      row.memberName = nil
      row.name:Hide()
      row.profs:Hide()
    end
  end

  local plan = self:Plan()
  local lines = self:PlanLines(plan)
  for i, fs in ipairs(ui.plan) do fs:SetText(lines[i]) end
  local notes = self:Notes(plan)
  ui.notes:SetText(table.concat(notes, "\n\n"))
  ui.post:SetEnabled(#lines > 0)
  self.lastPlan, self.lastLines, self.lastNotes = plan, lines, notes
end

function PlannerTab:Init()
  ns.RegisterCallback(self, "GROUP_PROFESSIONS", function(_, name, payload) PlannerTab:OnProfessions(name, payload) end)
  local pending
  local events = CreateFrame("Frame")
  events:RegisterEvent("GROUP_ROSTER_UPDATE")
  events:SetScript("OnEvent", function()
    if pending then pending:Cancel() end
    pending = ns.api.timer(PlannerTab.PROF_DELAY, function()
      pending = nil
      PlannerTab:SendProfessions()
      if ns.Window:IsShown() then PlannerTab:Refresh() end
    end)
  end)
end
