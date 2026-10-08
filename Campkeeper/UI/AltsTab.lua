local _, ns = ...
local L = ns.L
local Util = ns.Util

-- Alts tab: every character of the account with professions, camp items, recipes, blueprints and
-- the shared cooldown. Also feeds the minimap button tooltip.
local AltsTab = { ROWS = 12, ROW_HEIGHT = 32 }
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
    }
    l.name:SetPoint("TOPLEFT", 0, y)
    l.cooldown:SetPoint("TOPRIGHT", 0, y)
    l.details:SetPoint("TOPLEFT", 12, y - 14)
    l.details:SetPoint("RIGHT")
    l.details:SetJustifyH("LEFT")
    l.details:SetWordWrap(false)
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
      l.details:SetText(L["%s / camp items: %d / recipes: %s / blueprints: %s"]:format(
        r.professions ~= "" and r.professions or L["no professions"], r.items,
        r.recipes ~= "" and r.recipes or "-", r.blueprints))
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
