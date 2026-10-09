local _, ns = ...
local L = ns.L

-- Channels, sending and receiving. GUILD, PARTY/RAID and the hidden shared channel "Campkeeper".
-- Messages go out only on events: own fire/object placed, benefits parsed (camp seen), and replies
-- to a guild SYNC (at most two members answer, after a random 2-8 s, with fresh camps only).
-- While the client restricts outgoing addon messages they wait in a queue.
local Comm = { CHANNEL = "Campkeeper", JOIN_DELAY = 5, SYNC_DELAY = 10, SYNC_REPLIES = 2, REPLY_MIN = 2,
               REPLY_MAX = 8, MAX_REPLY_CAMPS = 20, FLUSH = 5, PRIORITY = "BULK" }
ns.Comm = Comm

local Protocol = ns.Protocol
local SOURCE = { GUILD = "guild", PARTY = "party", RAID = "party", INSTANCE_CHAT = "party", CHANNEL = "channel" }

local queue, pendingSync = {}, {}
local versionNoticeShown = false

local function sharing() return ns.db.profile.sharing end

local function restricted()
  local info = C_ChatInfo
  if not info then return false end
  return (info.InChatMessagingLockdown and info.InChatMessagingLockdown())
      or (info.AreOutgoingAddonChatMessagesRestricted and info.AreOutgoingAddonChatMessagesRestricted()) or false
end

local function playerName() return UnitName("player") end

local function shortName(sender)
  return Ambiguate and Ambiguate(sender, "none") or (sender:match("^[^-]+") or sender)
end

function Comm:ChannelID()
  local id = GetChannelName(self.CHANNEL)
  return (id and id > 0) and id or nil
end

function Comm:JoinChannel()
  if not sharing().channel or self:ChannelID() then return end
  JoinTemporaryChannel(self.CHANNEL)
  for i = 1, NUM_CHAT_WINDOWS or 1 do
    local frame = _G["ChatFrame" .. i]
    if frame then ChatFrame_RemoveChannel(frame, self.CHANNEL) end
  end
end

function Comm:LeaveChannel()
  if self:ChannelID() then LeaveChannelByName(self.CHANNEL) end
end

-- Where a broadcast goes right now.
function Comm:Distributions()
  local out = {}
  if IsInGuild() then out[#out + 1] = { "GUILD" } end
  if IsInRaid() then out[#out + 1] = { "RAID" } elseif IsInGroup() then out[#out + 1] = { "PARTY" } end
  local channel = sharing().channel and self:ChannelID()
  if channel then out[#out + 1] = { "CHANNEL", channel } end
  return out
end

function Comm:Send(msg, distribution, target)
  local text = Protocol:Encode(msg)
  if restricted() then
    queue[#queue + 1] = { text, distribution, target }
    ns.callbacks:Fire("COMM_SENT", distribution, true)
    return false
  end
  ns.addon:SendCommMessage(Protocol.PREFIX, text, distribution, target, self.PRIORITY)
  ns.callbacks:Fire("COMM_SENT", distribution, false)
  return true
end

function Comm:Flush()
  if #queue == 0 or restricted() then return end
  local pending = queue
  queue = {}
  for _, q in ipairs(pending) do
    ns.addon:SendCommMessage(Protocol.PREFIX, q[1], q[2], q[3], self.PRIORITY)
  end
end

function Comm:QueueLength() return #queue end

function Comm:Broadcast(msg)
  for _, d in ipairs(self:Distributions()) do self:Send(msg, d[1], d[2]) end
end

function Comm:ShareCamp(record)
  if record.mapID and record.x and record.y then self:Broadcast(Protocol:CampMessage(record)) end
end

-- Camps worth sending to a guild mate who just logged in.
function Comm:FreshCamps()
  local out = {}
  for _, r in ipairs(ns.CampStore:All()) do
    if r.confirmed and r.source ~= "channel" and r.mapID and r.x then out[#out + 1] = r end
    if #out >= self.MAX_REPLY_CAMPS then break end
  end
  return out
end

function Comm:RequestSync()
  if not IsInGuild() then return end
  self:Send({ v = Protocol.VERSION, t = "SYNC", id = ns.CampStore.GuidTail(UnitGUID("player")) .. "-" .. ns.api.serverTime() },
            "GUILD")
end

local function scheduleSyncReply(syncID)
  if pendingSync[syncID] then return end
  local state = { replies = {} }
  pendingSync[syncID] = state
  local delay = Comm.REPLY_MIN + ns.api.random() * (Comm.REPLY_MAX - Comm.REPLY_MIN)
  state.timer = ns.api.timer(delay, function()
    local n = 0
    for _ in pairs(state.replies) do n = n + 1 end
    if n < Comm.SYNC_REPLIES then
      for _, r in ipairs(Comm:FreshCamps()) do Comm:Send(Protocol:CampMessage(r, syncID), "GUILD") end
    end
  end)
end

local function handle(text, distribution, sender)
  local name = shortName(sender)
  if name == playerName() then return end
  local msg, reason = Protocol:Decode(text)
  if not msg then
    if reason == "version" and not versionNoticeShown then
      versionNoticeShown = true
      ns.addon:Print(L["Someone uses an incompatible Campkeeper version. Please update the addon."])
    end
    ns.log("comm", "dropped message from %s: %s", name, reason)
    return
  end
  local ok, why = Protocol:Validate(msg, name)
  if not ok then
    ns.log("comm", "dropped %s from %s: %s", tostring(msg.t), name, why)
    return
  end
  if msg.t == "CAMP" then
    local source = SOURCE[distribution]
    if not source then return end
    ns.CampStore:Add(Protocol:CampRecord(msg, source, name))
    if msg.r and pendingSync[msg.r] then pendingSync[msg.r].replies[name] = true end
  elseif msg.t == "SYNC" and distribution == "GUILD" and type(msg.id) == "string" then
    scheduleSyncReply(msg.id)
  elseif msg.t == "PROF" and SOURCE[distribution] == "party" and type(msg.p) == "table" then
    ns.callbacks:Fire("GROUP_PROFESSIONS", name, msg.p)
  end
end

-- AceComm callback. Nothing here may break the rest of the addon.
function Comm:OnMessage(text, distribution, sender)
  local ok, err = pcall(handle, text, distribution, sender)
  if not ok then ns.log("comm", "error handling message from %s: %s", tostring(sender), tostring(err)) end
end

function Comm:AddOptions()
  ns.Options:AddGroup("sharing", {
    type = "group", name = L["Sharing"], inline = true,
    args = {
      channel = {
        type = "toggle", name = L["Share camps in the shared channel"], width = "full", order = 1,
        desc = L["Guild and group sharing always stay on."],
        get = function() return sharing().channel end,
        set = function(_, v)
          sharing().channel = v
          if v then Comm:JoinChannel() else Comm:LeaveChannel() end
        end,
      },
    },
  })
end

function Comm:Init()
  ns.addon:RegisterComm(Protocol.PREFIX, function(_, text, distribution, sender) Comm:OnMessage(text, distribution, sender) end)
  ns.RegisterCallback(self, "CAMP_SHAREABLE", function(_, record)
    local ok, err = pcall(Comm.ShareCamp, Comm, record)
    if not ok then ns.log("comm", "error sharing camp: %s", tostring(err)) end
  end)
  ns.api.after(self.JOIN_DELAY, function() Comm:JoinChannel() end)
  ns.api.after(self.SYNC_DELAY, function() Comm:RequestSync() end)
  self.ticker = C_Timer.NewTicker(self.FLUSH, function() Comm:Flush() end)
end
