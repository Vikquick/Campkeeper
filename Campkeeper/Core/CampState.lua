local _, ns = ...

-- Where the player is relative to a camp, derived from three player auras:
--   AWAY     no camp aura
--   NEAR     "Campfire Nearby"      (aura near, permanent while in range)
--   SITTING  "Welcoming Campfire"   (aura sitting, 60 s countdown)
--   BUFFED   "Camp Benefits"        (aura benefits, 1 h)
-- The highest present aura wins. In combat (or when values are secret) nothing is read and the
-- state is frozen; it is rebuilt after combat.
local CampState = { AWAY = "AWAY", NEAR = "NEAR", SITTING = "SITTING", BUFFED = "BUFFED" }
ns.CampState = CampState

local RANK = { AWAY = 0, NEAR = 1, SITTING = 2, BUFFED = 3 }
CampState.RANK = RANK

local state = "AWAY"
local info = {}
local tracked = {} -- auraInstanceID -> true for the camp auras currently on the player
local dirty = false

local function campSpell(spellID)
  local a = ns.Catalog.auras
  return spellID == a.near or spellID == a.sitting or spellID == a.benefits
end

function CampState:Get() return state end
function CampState:Info() return info end

function CampState:SittingRemaining()
  if state ~= "SITTING" or not info.sittingExpires then return nil end
  return math.max(0, info.sittingExpires - ns.api.now())
end

function CampState:BenefitsRemaining()
  if not info.benefitsExpires then return nil end
  return math.max(0, info.benefitsExpires - ns.api.now())
end

-- Re-read the camp auras. Returns false when the state could not be determined (left frozen).
function CampState:Rebuild()
  if ns.api.inCombat() then
    dirty = true
    return false
  end
  local a = ns.Catalog.auras
  local near, sitting, benefits = ns.api.playerAura(a.near), ns.api.playerAura(a.sitting), ns.api.playerAura(a.benefits)
  if near == nil or sitting == nil or benefits == nil then
    dirty = true
    return false
  end
  dirty = false

  wipe(tracked)
  for _, aura in ipairs({ near, sitting, benefits }) do
    if aura then tracked[aura.instanceID] = true end
  end

  local new = benefits and "BUFFED" or sitting and "SITTING" or near and "NEAR" or "AWAY"
  local benefitsID = benefits and benefits.instanceID or nil
  local benefitsChanged = benefitsID ~= info.benefitsInstanceID

  info.near = near ~= false
  info.sittingExpires = sitting and sitting.expirationTime or nil
  info.benefitsExpires = benefits and benefits.expirationTime or nil
  info.benefitsInstanceID = benefitsID
  if benefitsChanged then info.benefits = nil end -- composition of a new aura is parsed again

  local old = state
  state = new
  if old ~= new then
    ns.callbacks:Fire("CAMP_STATE_CHANGED", old, new, info)
  end
  if benefitsChanged and benefits then
    ns.callbacks:Fire("CAMP_BENEFITS_GAINED", benefits.instanceID, info)
  end
  return true
end

-- Store the parsed composition of the current "Camp Benefits" aura.
function CampState:SetBenefits(instanceID, composition)
  if instanceID ~= info.benefitsInstanceID then return end
  info.benefits = composition
  ns.callbacks:Fire("CAMP_BENEFITS_PARSED", composition, info)
end

local function touchesCamp(updateInfo)
  if not updateInfo or updateInfo.isFullUpdate then return true end
  for _, aura in ipairs(updateInfo.addedAuras or {}) do
    -- a secret spellId cannot be compared: be safe and rebuild (which then freezes if needed)
    if ns.Util.isSecret(aura) or ns.Util.isSecret(aura.spellId) then return true end
    local ok, relevant = pcall(campSpell, aura.spellId)
    if not ok or relevant then return true end
  end
  for _, id in ipairs(updateInfo.updatedAuraInstanceIDs or {}) do
    if tracked[id] then return true end
  end
  for _, id in ipairs(updateInfo.removedAuraInstanceIDs or {}) do
    if tracked[id] then return true end
  end
  return false
end

-- UNIT_AURA for "player".
function CampState:OnUnitAura(updateInfo)
  if ns.api.inCombat() then
    dirty = true
    return
  end
  if dirty or touchesCamp(updateInfo) then self:Rebuild() end
end

-- PLAYER_REGEN_ENABLED / PLAYER_ENTERING_WORLD.
function CampState:OnCombatEnded()
  self:Rebuild()
end

function CampState:IsDirty() return dirty end
