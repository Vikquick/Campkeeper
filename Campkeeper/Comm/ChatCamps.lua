local _, ns = ...

-- Camps from ordinary chat: a message with a map pin and either a Campkeeper tag or a word about
-- a camp becomes an unconfirmed camp on the map, also when the sender has no addon. Tier, time
-- left and objects come only from a Campkeeper announcement (see Core/Announce.lua).
-- Nothing here may break the rest of the addon: the handler runs under pcall.
local ChatCamps = { RATE_LIMIT = 3, RATE_WINDOW = 60,
                    EVENTS = { "CHAT_MSG_CHANNEL", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY",
                               "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD" } }
ns.ChatCamps = ChatCamps

local Util = ns.Util

local function enabled() return ns.db.profile.sharing.chat ~= false end

-- Accepted report times per sender.
local recent = {}

local function rateLimited(sender, now)
  local times = recent[sender] or {}
  recent[sender] = times
  for i = #times, 1, -1 do
    if now - times[i] >= ChatCamps.RATE_WINDOW then table.remove(times, i) end
  end
  if #times >= ChatCamps.RATE_LIMIT then return true end
  times[#times + 1] = now
  return false
end

local function round(v) return math.floor(v + 0.5) end

local function handle(text, sender)
  -- secrets first: during a chat lockdown the client hands out values that must not be touched
  if Util.isSecret(text) or Util.isSecret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
  local name = ns.api.senderName(sender)
  if name == ns.api.unitFullName("player") then
    ns.Announce:OnOwnMessage(text) -- proof that an announcement went out; works with reading turned off
    return
  end
  if not enabled() then return end
  local p = ns.Announce:Parse(text)
  if not p or not (p.campkeeper or ns.Announce:Looks(text)) then return end
  if ns.api.isIgnored(name) then return end
  if p.x < 0 or p.x > 1 or p.y < 0 or p.y > 1 or not ns.api.mapInfo(p.mapID) then
    ns.log("chat", "dropped a camp report from %s: map %s, %s, %s", name, tostring(p.mapID), tostring(p.x), tostring(p.y))
    return
  end
  if p.minutes == 0 then return end -- the fire is going out right now
  if rateLimited(name, ns.api.now()) then
    ns.log("chat", "dropped a camp report from %s: rate", name)
    return
  end
  local now = ns.api.serverTime()
  ns.CampStore:Add({
    id = ("chat-%s-%d-%d-%d"):format(name, p.mapID, round(p.x * 1000), round(p.y * 1000)),
    source = "chat", mapID = p.mapID, x = p.x, y = p.y, tier = p.tier, objects = p.objects or {},
    expiresAt = p.minutes and (now + p.minutes * 60) or nil, reporters = { [name] = true }, lastSeen = now,
  })
end

function ChatCamps:OnChat(text, sender)
  local ok, err = pcall(handle, text, sender)
  if not ok then ns.log("chat", "error reading a chat message: %s", tostring(err)) end
end

function ChatCamps:Init()
  local events = CreateFrame("Frame")
  for _, e in ipairs(self.EVENTS) do events:RegisterEvent(e) end
  events:SetScript("OnEvent", function(_, _, text, sender) ChatCamps:OnChat(text, sender) end)
end
