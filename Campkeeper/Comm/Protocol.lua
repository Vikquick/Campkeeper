local _, ns = ...

-- Wire format of addon messages (prefix CAMPK), serialized with AceSerializer:
--   { v = 1, t = "CAMP", id, m = mapID, x = 0..1000, y = 0..1000, tier?, o = objects mask, p = placedAt?,
--     e = expiresAt?, r = syncID? }   one camp; r marks a reply to a guild SYNC
--   { v = 1, t = "SYNC", id }          guild members: please send your fresh camps
--   { v = 1, t = "PROF", p = { [skillLineID] = skill } }   professions, group only (planner)
-- The objects mask uses the catalog order: bit i = Catalog.order[i]. New objects are only ever
-- appended, so older clients ignore unknown high bits. Arithmetic, not the bit library: the
-- mask can exceed 32 bits (doubles are exact up to 53).
local Protocol = { PREFIX = "CAMPK", VERSION = 1, RATE_LIMIT = 3, RATE_WINDOW = 60, FUTURE_SLACK = 60,
                   MAX_ID = 48, DUPLICATE_TTL = 3600 }
ns.Protocol = Protocol

local Serializer = LibStub("AceSerializer-3.0")

function Protocol.Mask(objects)
  local mask = 0
  for i, key in ipairs(ns.Catalog.order) do
    if objects[key] then mask = mask + 2 ^ (i - 1) end
  end
  return mask
end

function Protocol.Unmask(mask)
  local objects = {}
  for i, key in ipairs(ns.Catalog.order) do
    if mask <= 0 then break end
    if mask % 2 == 1 then objects[key] = true end
    mask = math.floor(mask / 2)
  end
  return objects
end

local function coord(v) return math.floor(v * 1000 + 0.5) end

function Protocol:CampMessage(r, syncID)
  return { v = self.VERSION, t = "CAMP", id = r.id, m = r.mapID, x = coord(r.x), y = coord(r.y), tier = r.tier,
           o = self.Mask(r.objects), p = r.placedAt, e = r.expiresAt, r = syncID }
end

function Protocol:Encode(msg)
  return Serializer:Serialize(msg)
end

-- Returns msg, or nil and a reason ("corrupt", "version").
function Protocol:Decode(text)
  local ok, msg = Serializer:Deserialize(text)
  if not ok or type(msg) ~= "table" then return nil, "corrupt" end
  if msg.v ~= self.VERSION then return nil, "version" end
  return msg
end

-- Store record for a validated CAMP message.
function Protocol:CampRecord(msg, source, sender)
  return { id = msg.id, mapID = msg.m, x = msg.x / 1000, y = msg.y / 1000, tier = msg.tier,
           objects = self.Unmask(msg.o), placedAt = msg.p, expiresAt = msg.e, source = source,
           reporters = { [sender] = true }, lastSeen = ns.api.serverTime() }
end

local function isInt(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end

-- Validation state: recent message times per sender and processed (id, sender) pairs.
local recent, seen = {}, {}

function Protocol:ResetValidation()
  wipe(recent)
  wipe(seen)
end

local function rateLimited(sender, now)
  local times = recent[sender] or {}
  recent[sender] = times
  for i = #times, 1, -1 do
    if now - times[i] >= Protocol.RATE_WINDOW then table.remove(times, i) end
  end
  if #times >= Protocol.RATE_LIMIT then return true end
  times[#times + 1] = now
  return false
end

local function shape(msg)
  if msg.t ~= "CAMP" then return true end
  return type(msg.id) == "string" and #msg.id <= Protocol.MAX_ID and type(msg.m) == "number"
    and (msg.tier == nil or isInt(msg.tier, 1, 3)) and isInt(msg.o, 0, 2 ^ 53)
    and (msg.p == nil or type(msg.p) == "number") and (msg.e == nil or type(msg.e) == "number")
end

-- Returns true, or false and a reason:
-- "rate", "shape", "coords", "future", "expired", "map", "ignored", "duplicate".
function Protocol:Validate(msg, sender)
  local now = ns.api.serverTime()
  if ns.api.isIgnored(sender) then return false, "ignored" end
  if rateLimited(sender, ns.api.now()) then return false, "rate" end
  if not shape(msg) then return false, "shape" end
  if msg.t ~= "CAMP" then return true end
  if not (isInt(msg.x, 0, 1000) and isInt(msg.y, 0, 1000)) then return false, "coords" end
  if msg.p and msg.p > now + self.FUTURE_SLACK then return false, "future" end
  if msg.e and msg.e <= now then return false, "expired" end
  if not ns.api.mapInfo(msg.m) then return false, "map" end
  -- same camp, sender and content: an owner adding an object re-sends the same id with a new mask
  local key = ("%s@%s:%d:%s"):format(msg.id, sender, msg.o, tostring(msg.e))
  for k, at in pairs(seen) do if now - at > self.DUPLICATE_TTL then seen[k] = nil end end
  if seen[key] then return false, "duplicate" end
  seen[key] = now
  return true
end
