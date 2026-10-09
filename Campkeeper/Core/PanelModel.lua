local _, ns = ...

-- What the camp panel shows, computed without frames:
--   rows    { key, tier, status = "placed"|"placeable"|"covered", effect, item }
--   header  { fireTier, used, slots, fireRemaining, cooldownRemaining }
--   sitting { state, remaining, benefitsRemaining }
-- placed     the object is in the camp (benefits composition or own camp)
-- placeable  the best tier of a family with an item in the bags, enough skill and the shared
--            cooldown ready, unless that tier or a higher one is already placed
-- covered    a class buff on the player that this object does not stack with (wins over the rest)
local PanelModel = { OWN_CAMP_RANGE = 40 }
ns.PanelModel = PanelModel

-- Class buffs active on the player: { [buffKey] = true }.
function PanelModel:ActiveClassBuffs()
  local active = {}
  for key in pairs(ns.Catalog:ClassBuffs()) do
    for _, name in ipairs(ns.Catalog:ClassBuffNames(key)) do
      if ns.api.hasBuffNamed(name) then active[key] = true; break end
    end
  end
  return active
end

local function isCovered(object, activeBuffs)
  for _, buff in ipairs(object.exclusiveWith or {}) do
    if activeBuffs[buff] then return true end
  end
  return false
end

-- Own camp if the player stands at it.
local function ownCampHere()
  local camp = ns.OwnCamp:Get()
  if not camp then return nil end
  local d = ns.api.distance(ns.api.playerPosition(), camp)
  return (d and d <= PanelModel.OWN_CAMP_RANGE) and camp or nil
end

-- Objects in the camp: { [key] = effect or true }.
local function placedObjects(info, camp)
  local placed = {}
  if info.benefits then
    for _, o in ipairs(info.benefits.objects) do placed[o.key] = o.effect end
  end
  if camp then
    for key in pairs(camp.objects) do placed[key] = placed[key] or true end
  end
  return placed
end

-- Highest placed tier per family.
local function placedTiers(placed)
  local tiers = {}
  for key in pairs(placed) do
    local o = ns.Catalog:Get(key)
    if o and (tiers[o.family] or 0) < o.tier then tiers[o.family] = o.tier end
  end
  return tiers
end

function PanelModel:Build(activeBuffs)
  activeBuffs = activeBuffs or self:ActiveClassBuffs()
  local info = ns.CampState:Info()
  local camp = ownCampHere()
  local placed = placedObjects(info, camp)
  local tiers = placedTiers(placed)
  local cooldown = ns.OwnCamp:CooldownRemaining() or 0
  local rows = {}

  for _, o in ipairs(ns.Catalog:Objects()) do
    local effect = placed[o.key]
    if effect then
      rows[#rows + 1] = { key = o.key, tier = o.tier, status = "placed",
                          effect = type(effect) == "string" and effect or nil }
    end
  end

  local used = 0
  for _ in pairs(placed) do used = used + 1 end
  local slots = camp and ns.Catalog:Fire(camp.tier).slots or nil

  for familyKey, family in pairs(ns.Catalog:Families()) do
    local best
    for _, key in ipairs(family.objects) do
      local o = ns.Catalog:Get(key)
      if ns.Professions:ItemInBags(key) and ns.Professions:Skill(family.profession) >= o.skill then best = o end
    end
    local upgrade = best and (tiers[familyKey] or 0) < best.tier
    local hasRoom = not slots or used < slots or (tiers[familyKey] and best and best.replaces)
    if best and upgrade and hasRoom and cooldown == 0 then
      rows[#rows + 1] = { key = best.key, tier = best.tier, status = "placeable",
                          item = ns.Professions:ItemInBags(best.key) }
    end
  end

  for _, row in ipairs(rows) do
    if isCovered(ns.Catalog:Get(row.key), activeBuffs) then row.status = "covered" end
  end

  local order = { placed = 1, placeable = 2, covered = 3 }
  table.sort(rows, function(a, b)
    if order[a.status] ~= order[b.status] then return order[a.status] < order[b.status] end
    return a.key < b.key
  end)

  return {
    rows = rows,
    header = { fireTier = camp and camp.tier, used = used, slots = slots,
               fireRemaining = camp and ns.OwnCamp:FireRemaining(), cooldownRemaining = cooldown,
               boostedRest = ns.OwnCamp:BoostedRestRemaining() },
    sitting = { state = ns.CampState:Get(), remaining = ns.CampState:SittingRemaining(),
                benefitsRemaining = ns.CampState:BenefitsRemaining() },
  }
end
