local _, ns = ...

-- Camps the player knows about: own, seen (benefits received at someone's camp) and reported
-- by others. Stored in CampkeeperDB.global.camps[id]:
--   { id, mapID, x, y, wx, wy, instance, tier?, objects = { [key] = true }, placedAt?, expiresAt?,
--     lastSeen, source, reporters = { [name] = true }, confirmed }
-- Records on the same map within 30 yd whose lifetimes overlap are merged.
local CampStore = { MERGE_RANGE = 30, UNTIMED_TTL = 600, LIMIT = 200, CONFIRMATIONS = 2 }
ns.CampStore = CampStore

-- Higher rank = more precise coordinates and more trust.
CampStore.RANK = { channel = 1, party = 2, guild = 2, seen = 3, self = 4 }

local function camps() return ns.db.global.camps end

local function lifetime(r)
  local from = r.placedAt or r.lastSeen
  local to = r.expiresAt or (r.lastSeen + CampStore.UNTIMED_TTL)
  return from, to
end

local function overlaps(a, b)
  local a1, a2 = lifetime(a)
  local b1, b2 = lifetime(b)
  return a1 <= b2 and b1 <= a2
end

local function fillWorld(r)
  if not r.wx and r.mapID and r.x and r.y then
    r.wx, r.wy, r.instance = ns.api.mapToWorld(r.mapID, r.x, r.y)
  end
end

local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

local function updateConfirmed(r)
  r.confirmed = CampStore.RANK[r.source] >= CampStore.RANK.party or count(r.reporters) >= CampStore.CONFIRMATIONS
end

function CampStore:Distance(a, b)
  if a.mapID ~= b.mapID then return nil end
  return ns.api.distance(a, b)
end

local function findMatch(r)
  for _, other in pairs(camps()) do
    if other.id ~= r.id and overlaps(other, r) then
      local d = CampStore:Distance(other, r)
      if d and d <= CampStore.MERGE_RANGE then return other end
    end
  end
end

local function merge(into, r)
  local better = CampStore.RANK[r.source] > CampStore.RANK[into.source]
  if better then
    into.mapID, into.x, into.y, into.wx, into.wy, into.instance = r.mapID, r.x, r.y, r.wx, r.wy, r.instance
    into.source = r.source
    if r.expiresAt then into.expiresAt = r.expiresAt end
  end
  for key in pairs(r.objects or {}) do into.objects[key] = true end
  for name in pairs(r.reporters or {}) do into.reporters[name] = true end
  if r.tier and (not into.tier or r.tier > into.tier) then into.tier = r.tier end
  if r.placedAt and (not into.placedAt or r.placedAt < into.placedAt) then into.placedAt = r.placedAt end
  if r.expiresAt and not into.expiresAt then into.expiresAt = r.expiresAt end
  into.lastSeen = math.max(into.lastSeen, r.lastSeen)
  updateConfirmed(into)
end

-- Insert or merge a record. Returns the stored record.
function CampStore:Add(r)
  r.objects = r.objects or {}
  r.reporters = r.reporters or {}
  r.lastSeen = r.lastSeen or ns.api.serverTime()
  fillWorld(r)
  local stored = camps()[r.id] or findMatch(r)
  if stored and stored.id == r.id and r.source == "self" then
    stored.objects = r.objects -- own camp is authoritative: a replaced tier-1 object disappears
  end
  if stored then
    merge(stored, r)
  else
    stored = r
    updateConfirmed(stored)
    camps()[r.id] = stored
    self:EnforceLimit()
  end
  ns.callbacks:Fire("CAMPS_UPDATED", stored)
  return stored
end

function CampStore:Remove(id)
  if camps()[id] then
    camps()[id] = nil
    ns.callbacks:Fire("CAMPS_UPDATED")
  end
end

function CampStore:IsExpired(r, now)
  now = now or ns.api.serverTime()
  local _, to = lifetime(r)
  return to <= now
end

-- Drop expired records. Returns how many were removed.
function CampStore:Prune(now)
  now = now or ns.api.serverTime()
  local removed = 0
  for id, r in pairs(camps()) do
    if self:IsExpired(r, now) then camps()[id] = nil; removed = removed + 1 end
  end
  if removed > 0 then ns.callbacks:Fire("CAMPS_UPDATED") end
  return removed
end

-- Keep at most LIMIT records: the oldest channel reports go first, then the oldest of any source.
function CampStore:EnforceLimit()
  local list = {}
  for _, r in pairs(camps()) do list[#list + 1] = r end
  if #list <= self.LIMIT then return end
  table.sort(list, function(a, b)
    local ca, cb = a.source == "channel", b.source == "channel"
    if ca ~= cb then return ca end
    return a.lastSeen < b.lastSeen
  end)
  for i = 1, #list - self.LIMIT do camps()[list[i].id] = nil end
end

function CampStore:Get(id) return camps()[id] end

-- Live records, any order.
function CampStore:All()
  local out, now = {}, ns.api.serverTime()
  for _, r in pairs(camps()) do
    if not self:IsExpired(r, now) then out[#out + 1] = r end
  end
  return out
end

-- Short id prefix from a player GUID ("Player-1234-0ABCDEF1" -> "0ABCDEF1").
function CampStore.GuidTail(guid)
  return guid and guid:sub(-8) or "unknown"
end

local function ownRecord(camp)
  local objects = {}
  for key in pairs(camp.objects) do objects[key] = true end
  return { id = CampStore.GuidTail(UnitGUID("player")) .. "-" .. camp.placedAt, source = "self",
           mapID = camp.mapID, x = camp.x, y = camp.y, wx = camp.wx, wy = camp.wy, instance = camp.instance,
           tier = camp.tier, objects = objects, placedAt = camp.placedAt, expiresAt = camp.expiresAt,
           lastSeen = ns.api.serverTime() }
end

-- Benefits received away from the own camp: a camp of someone else, seen first hand.
local function seenRecord(composition)
  local pos = ns.api.playerPosition()
  if not pos or not pos.x then return nil end
  local own = ns.OwnCamp:Get()
  if own then
    local d = ns.api.distance(pos, own)
    if d and d <= CampStore.MERGE_RANGE then return nil end
  end
  local now = ns.api.serverTime()
  local objects = {}
  for _, o in ipairs(composition.objects) do objects[o.key] = true end
  return { id = CampStore.GuidTail(UnitGUID("player")) .. "-" .. now, source = "seen",
           mapID = pos.mapID, x = pos.x, y = pos.y, wx = pos.wx, wy = pos.wy, instance = pos.instance,
           objects = objects, lastSeen = now }
end

-- Records the player can vouch for (own camp, camp seen first hand) are announced with
-- CAMP_SHAREABLE(record) so the comm layer can send them.
function CampStore:Init()
  local function own(_, camp)
    local r = ownRecord(camp)
    CampStore:Add(r)
    ns.callbacks:Fire("CAMP_SHAREABLE", r)
  end
  ns.RegisterCallback(self, "OWN_CAMP_PLACED", own)
  ns.RegisterCallback(self, "OWN_CAMP_UPDATED", own)
  ns.RegisterCallback(self, "CAMP_BENEFITS_PARSED", function(_, composition)
    local r = composition and seenRecord(composition)
    if r then
      CampStore:Add(r)
      ns.callbacks:Fire("CAMP_SHAREABLE", r)
    end
  end)
  self:Prune()
  self.ticker = C_Timer.NewTicker(30, function() CampStore:Prune() end)
end
