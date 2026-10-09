local _, ns = ...

-- The player's own camp, the shared camping cooldown and the last known benefits.
--   char.ownCamp       { mapID, x, y, wx, wy, instance, tier, placedAt, expiresAt, objects = { [key] = placedAt } }
--   chars[*].cooldownReadyAt  server time when camping items can be used again (shared 1 h cooldown)
--   char.lastBenefits  { objects = { {key, tier, effect} }, expiresAt } — survives logout
local OwnCamp = { ATTACH_RANGE = 30, ATTEMPT_WINDOW = 2, COOLDOWN_MIN = 2 }
ns.OwnCamp = OwnCamp

-- UI_ERROR_MESSAGE types seen when placing (client 1.60.1).
OwnCamp.ERRORS = { [57] = "blocked", [58] = "cooldown" }

local attempt -- { key, at } of the last placement attempt

function OwnCamp:Get()
  local camp = ns.db.char.ownCamp
  if camp and camp.expiresAt and camp.expiresAt <= ns.api.serverTime() then
    ns.db.char.ownCamp = nil
    return nil
  end
  return camp
end

function OwnCamp:FireRemaining()
  local camp = self:Get()
  return camp and math.max(0, camp.expiresAt - ns.api.serverTime()) or nil
end

local function placeFire(fire)
  local pos = ns.api.playerPosition() or {}
  local now = ns.api.serverTime()
  local camp = { mapID = pos.mapID, x = pos.x, y = pos.y, wx = pos.wx, wy = pos.wy, instance = pos.instance,
                 tier = fire.tier, placedAt = now, expiresAt = now + fire.burn, objects = {} }
  ns.db.char.ownCamp = camp
  ns.callbacks:Fire("OWN_CAMP_PLACED", camp)
end

local function placeObject(object)
  local camp = OwnCamp:Get()
  if not camp then return end
  local d = ns.api.distance(ns.api.playerPosition(), camp)
  if not d or d > OwnCamp.ATTACH_RANGE then return end
  if object.replaces then camp.objects[object.replaces] = nil end
  camp.objects[object.key] = ns.api.serverTime()
  ns.callbacks:Fire("OWN_CAMP_UPDATED", camp, object.key)
end

-- UNIT_SPELLCAST_SUCCEEDED for "player".
function OwnCamp:OnSpellSucceeded(spellID)
  local placed = ns.Catalog:ByPlaceSpell(spellID)
  if not placed then return end
  attempt = nil
  if placed.isFire then placeFire(placed) else placeObject(placed) end
  self:UpdateCooldown()
end

-- Called when the player tries to place something (panel button, UNIT_SPELLCAST_SENT).
function OwnCamp:NoteAttempt(key)
  attempt = { key = key, at = ns.api.now() }
end

-- UI_ERROR_MESSAGE: report placement failures that follow an attempt.
function OwnCamp:OnUIError(errorType, message)
  if not attempt or ns.api.now() - attempt.at > self.ATTEMPT_WINDOW then return end
  ns.callbacks:Fire("CAMP_UI_ERROR", errorType, message, attempt.key)
  local reason = self.ERRORS[errorType]
  if not reason then return end
  local key = attempt.key
  attempt = nil
  ns.callbacks:Fire("CAMP_PLACE_FAILED", key, reason)
end

-- Read the shared cooldown from any camping item in the bags; keep the last value otherwise.
function OwnCamp:UpdateCooldown()
  local c = ns.Professions:Char()
  local item
  for id in pairs(c.items) do item = id; break end
  if not item then return c.cooldownReadyAt end
  local start, duration = ns.api.itemCooldown(item)
  if not start then return c.cooldownReadyAt end
  local readyAt
  if duration and duration > self.COOLDOWN_MIN and start > 0 then
    readyAt = math.floor(ns.api.serverTime() + (start + duration - ns.api.now()) + 0.5)
  else
    readyAt = ns.api.serverTime() -- ready (a global cooldown is not the camping cooldown)
  end
  if readyAt ~= c.cooldownReadyAt then
    c.cooldownReadyAt = readyAt
    ns.callbacks:Fire("CAMP_COOLDOWN_UPDATED", readyAt)
  end
  return readyAt
end

-- Seconds until the shared cooldown is ready (0 = ready), nil if never seen.
function OwnCamp:CooldownRemaining(charRecord)
  local readyAt = (charRecord or ns.Professions:Char()).cooldownReadyAt
  return readyAt and math.max(0, readyAt - ns.api.serverTime()) or nil
end

-- CAMP_BENEFITS_PARSED: remember composition and end time for the next session and the alts tab.
function OwnCamp:OnBenefitsParsed(composition, info)
  if not composition or not info.benefitsExpires then return end
  local objects = {}
  for _, o in ipairs(composition.objects) do
    objects[#objects + 1] = { key = o.key, tier = o.tier, effect = o.effect }
  end
  ns.db.char.lastBenefits = {
    objects = objects,
    expiresAt = math.floor(ns.api.serverTime() + (info.benefitsExpires - ns.api.now()) + 0.5),
  }
end

-- Last benefits if they have not expired yet.
function OwnCamp:LastBenefits()
  local b = ns.db.char.lastBenefits
  if b and b.expiresAt > ns.api.serverTime() then return b end
  return nil
end

function OwnCamp:BenefitsRemaining()
  local live = ns.CampState:BenefitsRemaining()
  if live then return live end
  local b = self:LastBenefits()
  return b and (b.expiresAt - ns.api.serverTime()) or nil
end

-- Boosted Rest: shown only once its aura spell ID is known (catalog auras.boostedRest).
function OwnCamp:BoostedRestRemaining()
  local spell = ns.Catalog.auras.boostedRest
  if not spell then return nil end
  local aura = ns.api.playerAura(spell)
  if not aura then return nil end
  if not aura.expirationTime or aura.expirationTime == 0 then return nil end
  local remaining = math.max(0, aura.expirationTime - ns.api.now())
  ns.Professions:Char().boostedRestUntil = math.floor(ns.api.serverTime() + remaining + 0.5)
  return remaining
end
