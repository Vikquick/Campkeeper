local _, ns = ...
local L = ns.L
local Util = ns.Util

-- Alts tab: every character of the account with professions, camp items, recipes, blueprints and
-- the shared cooldown. Also feeds the minimap button tooltip.
-- LIVE: the window refreshes this tab every second (cooldown timers).
local AltsTab = { ROWS = 9, ROW_HEIGHT = 46, LIVE = true }
ns.AltsTab = AltsTab

local function cooldownText(c)
  local remaining = ns.OwnCamp:CooldownRemaining(c)
  if remaining == nil then return L["unknown"] end
  if remaining <= 0 then return L["ready"] end
  return Util.formatDuration(remaining)
end

-- { { key, name, realm, class, professions = "Mining 150, Cooking 225", items = n, recipes = "...",
--     blueprints, cooldown, ready } } sorted by name; the current character first.
function AltsTab:Rows()
  local current = ns.db.keys.char
  local rows = {}
  for key, c in pairs(ns.db.global.chars) do
    local profs = {}
    for prof, p in pairs(c.professions or {}) do
      profs[#profs + 1] = ("%s %d"):format(L[ns.CatalogTab.PROFESSION_NAMES[prof]], p.skill)
    end
    table.sort(profs)
    local items = 0
    for _, n in pairs(c.items or {}) do items = items + n end
    local recipes = {}
    for objectKey in pairs(c.recipes or {}) do recipes[#recipes + 1] = ns.Catalog:Name(objectKey) end
    table.sort(recipes)
    local remaining = ns.OwnCamp:CooldownRemaining(c)
    rows[#rows + 1] = {
      key = key, name = c.name, realm = c.realm, class = c.class, current = key == current,
      professions = table.concat(profs, ", "), items = items, recipes = table.concat(recipes, ", "),
      -- whether a blueprint is learned cannot be read from the client yet (open question Q4)
      blueprints = L["unknown"],
      cooldown = cooldownText(c), ready = remaining ~= nil and remaining <= 0,
      boostedRest = ns.OwnCamp:BoostedRestLeft(c),
    }
  end
  table.sort(rows, function(a, b)
    if a.current ~= b.current then return a.current end
    return a.key < b.key
  end)
  return rows
end

local lines = {}

function AltsTab:Create(parent)
  for i = 1, self.ROWS do
    local y = -(i - 1) * self.ROW_HEIGHT
    local l = {
      name = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
      cooldown = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
      details = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      recipes = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
    }
    l.name:SetPoint("TOPLEFT", 0, y)
    l.cooldown:SetPoint("TOPRIGHT", 0, y)
    for n, fs in ipairs({ l.details, l.recipes }) do
      fs:SetPoint("TOPLEFT", 12, y - 2 - n * 13)
      fs:SetPoint("RIGHT")
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(false)
    end
    lines[i] = l
  end
end

function AltsTab:Refresh()
  local rows = self:Rows()
  for i, l in ipairs(lines) do
    local r = rows[i]
    if r then
      local color = RAID_CLASS_COLORS and r.class and RAID_CLASS_COLORS[r.class]
      l.name:SetText(("%s - %s"):format(r.name or "?", r.realm or "?"))
      if color then l.name:SetTextColor(color.r, color.g, color.b) end
      l.cooldown:SetText(L["Camping cooldown: %s"]:format(r.cooldown))
      if i == 1 then self.lastCooldownText = l.cooldown:GetText() end
      l.details:SetText(L["%s / camp items: %d"]:format(r.professions ~= "" and r.professions or L["no professions"], r.items))
      local recipes = L["Recipes: %s / blueprints: %s"]:format(r.recipes ~= "" and r.recipes or "-", r.blueprints)
      if r.boostedRest then
        recipes = ("%s / %s: %s"):format(recipes, ns.OwnCamp:BoostedRestName(), Util.formatDuration(r.boostedRest))
      end
      l.recipes:SetText(recipes)
      for _, fs in pairs(l) do fs:Show() end
    else
      for _, fs in pairs(l) do fs:Hide() end
    end
  end
end

-- Minimap tooltip lines: "Name: ready / 12:30".
function AltsTab:TooltipLines()
  local out = {}
  for _, r in ipairs(self:Rows()) do out[#out + 1] = { r.name, r.cooldown, r.ready } end
  return out
end

function AltsTab:Init()
  ns.RegisterCallback(self, "MINIMAP_TOOLTIP", function(_, tooltip)
    tooltip:AddLine(L["Camping cooldown"], 1, 0.82, 0)
    for _, line in ipairs(self:TooltipLines()) do
      if line[3] then tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 0.3, 1, 0.3)
      else tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) end
    end
  end)
end
