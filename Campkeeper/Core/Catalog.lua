local _, ns = ...

-- Lookups over the generated ns.CatalogData plus localized names from the client.
-- Names load asynchronously: until then Name() returns a placeholder, and CATALOG_UPDATED(key)
-- fires once the real name arrives.
local Catalog = {}
ns.Catalog = Catalog

local data = ns.CatalogData
local byItem, byPlaceSpell, waitingItem, waitingSpell = {}, {}, {}, {}

local function index()
  for key, o in pairs(data.objects) do
    o.key = key
    for _, item in ipairs(o.items) do byItem[item] = o end
    for _, spell in ipairs(o.place) do byPlaceSpell[spell] = o end
  end
  for _, f in ipairs(data.fires) do
    f.key = "fire" .. f.tier
    f.isFire = true
    byItem[f.item] = f
    if f.place then byPlaceSpell[f.place] = f end
  end
end
index()

Catalog.auras = data.auras
Catalog.order = data.order

function Catalog:Get(key) return data.objects[key] end
function Catalog:Fire(tier) return data.fires[tier] end
function Catalog:Fires() return data.fires end
function Catalog:Family(key) return data.families[key] end
function Catalog:Families() return data.families end
function Catalog:Profession(key) return data.professions[key] end
function Catalog:ClassBuff(key) return data.classBuffs[key] end
function Catalog:ClassBuffs() return data.classBuffs end

-- Object or fire placed by this item / spell.
function Catalog:ByItem(itemID) return byItem[itemID] end
function Catalog:ByPlaceSpell(spellID) return byPlaceSpell[spellID] end

-- The tier-1 object this one replaces, or nil.
function Catalog:Replaces(key)
  local o = data.objects[key]
  return o and o.replaces
end

-- Every object of the same family, lowest tier first.
function Catalog:Chain(key)
  local o = data.objects[key]
  return o and data.families[o.family].objects
end

function Catalog:Objects()
  local out = {}
  for _, key in ipairs(data.order) do out[#out + 1] = data.objects[key] end
  return out
end

local function entry(key)
  return data.objects[key] or (key:match("^fire%d$") and data.fires[tonumber(key:sub(5))])
end

local function firstItem(e) return e.items and e.items[1] or e.item end

-- Localized display name. Objects use their item name; fires the name of their placement spell.
function Catalog:Name(key)
  local e = entry(key)
  if not e then return nil end
  local name
  if e.isFire then
    name = e.place and ns.api.spellName(e.place)
    if not name and e.place then waitingSpell[e.place] = key; ns.api.requestSpell(e.place) end
  else
    local item = firstItem(e)
    name = ns.api.itemName(item)
    if not name then waitingItem[item] = key; ns.api.requestItem(item) end
  end
  return name or ns.L["Loading..."], name ~= nil
end

-- All client names that can identify this object in the "Camp Benefits" tooltip:
-- item names and placement spell names (they differ for a few objects).
function Catalog:Names(key)
  local e, out, seen = entry(key), {}, {}
  if not e then return out end
  local function add(n) if n and not seen[n] then seen[n] = true; out[#out + 1] = n end end
  for _, item in ipairs(e.items or { e.item }) do add(ns.api.itemName(item)) end
  for _, spell in ipairs(type(e.place) == "table" and e.place or { e.place }) do add(ns.api.spellName(spell)) end
  return out
end

function Catalog:Icon(key)
  local e = entry(key)
  return e and ns.api.itemIcon(firstItem(e))
end

-- Effect text from the placement spell description (client language).
function Catalog:Description(key)
  local e = entry(key)
  if not e then return nil end
  local spell = type(e.place) == "table" and e.place[1] or e.place
  local text = spell and ns.api.spellDescription(spell)
  if (not text or text == "") and spell then
    waitingSpell[spell] = key
    ns.api.requestSpell(spell)
    return nil
  end
  return text
end

-- Localized names of a class buff (all ranks share a name; greater versions have their own).
function Catalog:ClassBuffNames(buffKey)
  local b, out = data.classBuffs[buffKey], {}
  if not b then return out end
  for _, spell in ipairs(b.spells) do
    local n = ns.api.spellName(spell)
    if n then out[#out + 1] = n else ns.log("catalog", "class buff %s: no name for spell %d", buffKey, spell) end
  end
  return out
end

-- Forwarded from ITEM_DATA_LOAD_RESULT / SPELL_DATA_LOAD_RESULT by the addon glue.
function Catalog:OnItemLoaded(itemID, success)
  local key = waitingItem[itemID]
  if not key then return end
  waitingItem[itemID] = nil
  if success then ns.callbacks:Fire("CATALOG_UPDATED", key)
  else ns.log("catalog", "item %d (%s) failed to load", itemID, key) end
end

function Catalog:OnSpellLoaded(spellID, success)
  local key = waitingSpell[spellID]
  if not key then return end
  waitingSpell[spellID] = nil
  if success then ns.callbacks:Fire("CATALOG_UPDATED", key)
  else ns.log("catalog", "spell %d (%s) failed to load", spellID, key) end
end
