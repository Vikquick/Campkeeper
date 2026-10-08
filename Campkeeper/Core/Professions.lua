local _, ns = ...

-- Per-character camp data: professions and skills, camp items in bags, known camp recipes.
-- Stored in CampkeeperDB.global.chars["Name - Realm"] so the alts tab can show every character.
local Professions = {}
ns.Professions = Professions

local skillLineToKey

local function professionKey(skillLine)
  if not skillLineToKey then
    skillLineToKey = {}
    for key, id in pairs(ns.CatalogData.professions) do skillLineToKey[id] = key end
  end
  return skillLineToKey[skillLine]
end

-- Record of the logged-in character (created on first use).
function Professions:Char()
  local key = ns.db.keys.char
  local chars = ns.db.global.chars
  local c = chars[key]
  if not c then
    local _, class = UnitClass("player")
    c = { name = UnitName("player"), realm = GetRealmName(), class = class,
          professions = {}, items = {}, recipes = {} }
    chars[key] = c
  end
  return c
end

function Professions:ScanProfessions()
  local profs = ns.api.professions()
  if not profs then return end
  local c = self:Char()
  wipe(c.professions)
  for skillLine, p in pairs(profs) do
    local key = professionKey(skillLine)
    if key then
      c.professions[key] = { skill = p.skill, max = p.max }
    else
      ns.log("professions", "unknown skill line %s (%s)", tostring(skillLine), tostring(p.name))
    end
  end
  ns.callbacks:Fire("PROFESSIONS_UPDATED", "professions")
end

-- Every item that places a camp object or fire.
local function campItems()
  local items = {}
  for _, o in ipairs(ns.Catalog:Objects()) do
    for _, item in ipairs(o.items) do items[#items + 1] = item end
  end
  for _, f in ipairs(ns.Catalog:Fires()) do items[#items + 1] = f.item end
  return items
end

function Professions:ScanBags()
  local c = self:Char()
  local changed = false
  for _, item in ipairs(campItems()) do
    local n = ns.api.itemCount(item) or 0
    if n == 0 then n = nil end
    if c.items[item] ~= n then c.items[item] = n; changed = true end
  end
  if changed then ns.callbacks:Fire("PROFESSIONS_UPDATED", "items") end
end

-- Known camp recipes. Without the profession window open only IsPlayerSpell is available;
-- with it open, the recipe list is authoritative.
function Professions:ScanRecipes(fromWindow)
  local c = self:Char()
  local changed = false
  for _, o in ipairs(ns.Catalog:Objects()) do
    if o.craft then
      local known
      if fromWindow then known = ns.api.recipeLearned(o.craft) end
      if known == nil then known = ns.api.isPlayerSpell(o.craft) end
      if known ~= nil then
        known = known or nil
        if c.recipes[o.key] ~= known then c.recipes[o.key] = known; changed = true end
      end
    end
  end
  if changed then ns.callbacks:Fire("PROFESSIONS_UPDATED", "recipes") end
end

function Professions:ScanAll()
  self:ScanProfessions()
  self:ScanBags()
  self:ScanRecipes(false)
  self:Char().updated = ns.api.serverTime()
end

-- Skill of the current character in a profession (catalog key), or 0.
function Professions:Skill(professionKey)
  local p = self:Char().professions[professionKey]
  return p and p.skill or 0
end

-- First item in bags that places this object, or nil.
function Professions:ItemInBags(objectKey)
  local o = ns.Catalog:Get(objectKey) or ns.Catalog:Fire(tonumber((objectKey or ""):match("^fire(%d)$") or 0))
  if not o then return nil end
  local items = self:Char().items
  for _, item in ipairs(o.items or { o.item }) do
    if items[item] then return item end
  end
  return nil
end

function Professions:KnowsRecipe(objectKey)
  return self:Char().recipes[objectKey] == true
end
