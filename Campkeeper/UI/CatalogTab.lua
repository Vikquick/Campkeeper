local _, ns = ...
local L = ns.L

-- Catalog tab: profession x tier grid. Cooking's tier-1 cell is the basic campfire.
local CatalogTab = { ROW_HEIGHT = 30, NAME_WIDTH = 130 }
ns.CatalogTab = CatalogTab

CatalogTab.PROFESSION_NAMES = {
  alchemy = "Alchemy", blacksmithing = "Blacksmithing", enchanting = "Enchanting", engineering = "Engineering",
  first_aid = "First Aid", fishing = "Fishing", herbalism = "Herbalism", leatherworking = "Leatherworking",
  mining = "Mining", skinning = "Skinning", tailoring = "Tailoring", cooking = "Cooking",
}

-- Families in catalog order.
local function familyOrder()
  local seen, out = {}, {}
  for _, o in ipairs(ns.Catalog:Objects()) do
    if not seen[o.family] then seen[o.family] = true; out[#out + 1] = o.family end
  end
  return out
end

-- { { profession, name, playerSkill?, cells = { [tier] = { key, name, skill, replaces?, known, fire? } } } }
function CatalogTab:Grid()
  local char = ns.Professions:Char()
  local rows = {}
  for _, familyKey in ipairs(familyOrder()) do
    local family = ns.Catalog:Family(familyKey)
    local p = char.professions[family.profession]
    local row = { profession = family.profession, name = L[self.PROFESSION_NAMES[family.profession]],
                  playerSkill = p and p.skill, cells = {} }
    for _, key in ipairs(family.objects) do
      local o = ns.Catalog:Get(key)
      row.cells[o.tier] = { key = key, name = ns.Catalog:Name(key), skill = o.skill,
                            replaces = o.replaces and ns.Catalog:Name(o.replaces), known = ns.Professions:KnowsRecipe(key) }
    end
    if family.profession == "cooking" and not row.cells[1] then
      local fire = ns.Catalog:Fire(1)
      row.cells[1] = { key = "fire1", name = ns.Catalog:Name("fire1"), skill = fire.skill, fire = true, known = false }
    end
    rows[#rows + 1] = row
  end
  return rows
end

local frames = {}

local function cellTooltip(self)
  local c = self.cell
  if not c then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(c.name)
  local desc = ns.Catalog:Description(c.key)
  if desc then GameTooltip:AddLine(desc, 1, 1, 1, true) end
  GameTooltip:AddLine(L["Requires: %s (%d)"]:format(self.professionName, c.skill), 1, 0.82, 0)
  if c.replaces then GameTooltip:AddLine(L["Replaces: %s"]:format(c.replaces), 0.6, 0.8, 1) end
  if c.known then GameTooltip:AddLine(L["You know how to make it"], 0.3, 1, 0.3) end
  GameTooltip:Show()
end

function CatalogTab:Create(parent)
  frames.parent = parent
  local colWidth = (parent:GetWidth() > 0 and parent:GetWidth() or 676) - self.NAME_WIDTH
  colWidth = math.floor(colWidth / 3)
  for t = 1, 3 do
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", self.NAME_WIDTH + (t - 1) * colWidth, 0)
    h:SetText(L["Tier %d"]:format(t))
  end
  frames.rows = {}
  for i = 1, 12 do
    local y = -18 - (i - 1) * self.ROW_HEIGHT
    local r = { label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight"), cells = {} }
    r.label:SetPoint("TOPLEFT", 0, y - 6)
    r.label:SetWidth(self.NAME_WIDTH - 6)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    for t = 1, 3 do
      local b = CreateFrame("Button", nil, parent)
      b:SetSize(colWidth - 4, self.ROW_HEIGHT - 2)
      b:SetPoint("TOPLEFT", self.NAME_WIDTH + (t - 1) * colWidth, y)
      b.icon = b:CreateTexture(nil, "ARTWORK")
      b.icon:SetSize(24, 24)
      b.icon:SetPoint("LEFT")
      b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 4, 0)
      b.name:SetPoint("RIGHT")
      b.name:SetJustifyH("LEFT")
      b.name:SetWordWrap(false)
      b.info = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      b.info:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 4, 0)
      b.info:SetJustifyH("LEFT")
      b:SetScript("OnEnter", cellTooltip)
      b:SetScript("OnLeave", function() GameTooltip:Hide() end)
      r.cells[t] = b
    end
    frames.rows[i] = r
  end
end

function CatalogTab:Refresh()
  if not frames.rows then return end
  for i, row in ipairs(self:Grid()) do
    local r = frames.rows[i]
    local skill = row.playerSkill and (" (" .. row.playerSkill .. ")") or ""
    r.label:SetText(row.name .. skill)
    r.label:SetTextColor(row.playerSkill and 1 or 0.6, row.playerSkill and 0.82 or 0.6, row.playerSkill and 0 or 0.6)
    for t = 1, 3 do
      local b, c = r.cells[t], row.cells[t]
      b.cell, b.professionName = c, row.name
      if c then
        b.icon:SetTexture(ns.Catalog:Icon(c.key))
        b.name:SetText(c.name)
        local info = L["skill %d"]:format(c.skill)
        if c.known then info = info .. ", |cff4cff4c" .. L["known"] .. "|r" end
        b.info:SetText(info)
        b:Show()
      else
        b:Hide()
      end
    end
  end
end
