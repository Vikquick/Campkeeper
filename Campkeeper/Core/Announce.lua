local _, ns = ...
local L = ns.L

-- A camp as one line of ordinary chat, readable and clickable without the addon:
--   <fire>, <used>/<places> - <objects>. <time left>. <map pin> (Campkeeper T<tier> <minutes>m #<objects>)
-- The text is in the language the player chose (the client's by default). The tag at the end
-- carries what is known of the fire tier, the minutes left and the objects (as a code), so another
-- Campkeeper understands the announcement whatever language it is written in.
-- Build and Parse are pure: no frames, no chat.
local Announce = { MAX = 255, INTERVAL = 120, TAG = "Campkeeper", CAMP_RANGE = 40, CONFIRM_WAIT = 5 }
ns.Announce = Announce

local Util = ns.Util

local LINK = "|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"
-- The text inside the brackets must be exactly what the client itself puts there, or the link is
-- not accepted in chat. The client's MAP_PIN_HYPERLINK already starts with this pin icon.
local PIN_ICON = "|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a "
local LINK_PATTERN = "|Hworldmap:(%d+):(%d+):(%d+)|h"
-- The tag: "(Campkeeper T2 7m #k3f)". Only what is known is written: T<tier>, <minutes>m,
-- #<objects code>; a camp nothing is known about gets a bare "(Campkeeper)".
local TAG_PATTERN = "%(" .. Announce.TAG .. "([^)]*)%)"
-- The two phrases of an announcement in the languages Data/Names.lua has names for.
local PHRASES = {
  enUS = { left = "%d min left.", camp = "Camp here" },
  ruRU = { left = "Ещё %d мин.", camp = "Лагерь здесь" },
}
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local MAX_CODE = 8 -- base-36 digits; 35 objects need 7
-- Words that make a message with a map pin a camp report. Latin ones must start a word
-- ("champion" is not a camp); Cyrillic is matched as plain text, after Util.lower folds case and ё.
local LATIN_WORDS = { "camp", "lager", "hoguera", "fogata" }
local PLAIN_WORDS = { "лагер", "костер", "кострищ" }

-- ASCII only: %p, %s and %a follow the C locale and can match bytes of UTF-8 letters.
local PUNCT, SPACES = "[!-/:-@%[-`{-~]", "[ \t\r\n]+"

local function round(v) return math.floor(v + 0.5) end

local function spaced(text) return (text:gsub(PUNCT, " "):gsub(SPACES, " ")) end

function Announce:Link(mapID, x, y)
  local text = MAP_PIN_HYPERLINK or (PIN_ICON .. "Map Pin Location")
  if not text:find("|A:", 1, true) then text = PIN_ICON .. text end
  return LINK:format(mapID, round(x * 10000), round(y * 10000), text)
end

-- Minutes until the fire goes out, rounded up; nil when unknown.
local function minutesLeft(camp, now)
  if not camp.expiresAt then return nil end
  return math.max(0, math.ceil((camp.expiresAt - now) / 60))
end

-- Names and phrases for an announcement: fireName(tier), objectName(key), "N min left", "Camp".
-- The client's own names unless the player chose a language Data/Names.lua carries.
local function wording(language)
  local data, phrases = ns.NamesData and ns.NamesData[language], PHRASES[language]
  if not (data and phrases) then
    return function(tier) return (ns.Catalog:Name("fire" .. tier)) end,
           function(key) return (ns.Catalog:Name(key)) end, L["%d min left."], L["Camp here"]
  end
  return function(tier) return data.fires[tier] end, function(key) return data.objects[key] end,
         phrases.left, phrases.camp
end

-- The objects of a camp as the tag carries them: the bit mask in catalog order (the same as in
-- the CAMPK protocol: new objects are only ever appended) written in base 36.
local function encode(objects)
  local mask = 0
  for i, key in ipairs(ns.Catalog.order) do
    if objects and objects[key] then mask = mask + 2 ^ (i - 1) end
  end
  if mask == 0 then return nil end -- nothing to tell
  local out = ""
  while mask > 0 do
    local digit = mask % 36
    out = DIGITS:sub(digit + 1, digit + 1) .. out
    mask = (mask - digit) / 36
  end
  return out
end

-- { [key] = true } from a code; empty for a missing or impossible one. Plain arithmetic, not
-- tonumber(code, 36): that goes through a 32-bit integer on Windows and the mask needs 35 bits.
local function decode(code)
  local objects, mask = {}, 0
  if #code == 0 or #code > MAX_CODE then return objects end
  for i = 1, #code do
    local digit = DIGITS:find(code:sub(i, i), 1, true)
    if not digit then return objects end
    mask = mask * 36 + digit - 1
  end
  if mask >= 2 ^ #ns.Catalog.order then return objects end
  for _, key in ipairs(ns.Catalog.order) do
    if mask <= 0 then break end
    if mask % 2 == 1 then objects[key] = true end
    mask = math.floor(mask / 2)
  end
  return objects
end

-- language: "enUS", "ruRU", or nil/"client" for the names of the client.
function Announce:Build(camp, now, language)
  local fireName, objectName, leftPhrase, campPhrase = wording(language)
  local fire = camp.tier and ns.Catalog:Fire(camp.tier)
  local names = {}
  for _, o in ipairs(ns.Catalog:Objects()) do
    if camp.objects and camp.objects[o.key] then names[#names + 1] = objectName(o.key) end
  end
  local head = fire and ("%s, %d/%d"):format(fireName(camp.tier), #names, fire.slots) or campPhrase
  local minutes = minutesLeft(camp, now)
  local tail = (minutes and minutes > 0) and (" " .. leftPhrase:format(minutes)) or ""
  local tag, code = { self.TAG }, encode(camp.objects)
  if camp.tier then tag[#tag + 1] = "T" .. camp.tier end
  if minutes then tag[#tag + 1] = minutes .. "m" end
  if code then tag[#tag + 1] = "#" .. code end
  tail = ("%s %s (%s)"):format(tail, self:Link(camp.mapID, camp.x, camp.y), table.concat(tag, " "))
  -- the chat limit counts bytes: add names while the whole message fits, then "+N" for the rest
  local list = ""
  for i, name in ipairs(names) do
    local nextList = (i == 1) and (" - " .. name) or (list .. ", " .. name)
    local rest = #names - i
    local reserve = rest > 0 and #(", +" .. rest) or 0
    if #head + #nextList + reserve + 1 + #tail > self.MAX then
      list = list .. (i == 1 and (" - +" .. #names) or (", +" .. (#names - i + 1)))
      break
    end
    list = nextList
  end
  return head .. list .. "." .. tail
end

-- Text without hyperlinks and colour codes, lowercased, punctuation as spaces, padded with spaces.
local function words(text)
  text = text:gsub("|H.-|h.-|h", " "):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", " ")
  return " " .. spaced(Util.lower(text)) .. " "
end

-- Whether the text talks about a camp (see the word lists above).
function Announce:Looks(text)
  local plain = words(text)
  for _, w in ipairs(LATIN_WORDS) do
    if plain:find("%f[a-z]" .. w) then return true end
  end
  for _, w in ipairs(PLAIN_WORDS) do
    if plain:find(w, 1, true) then return true end
  end
  return false
end

-- A chat line with a map pin: { mapID, x, y, campkeeper, tier?, minutes?, objects? }; nil without a pin.
-- Tier, minutes and objects are read only from the tag of a Campkeeper announcement, never from
-- the words around it, so the language of the message does not matter.
function Announce:Parse(text)
  local mapID, x, y = text:match(LINK_PATTERN)
  if not mapID then return nil end
  local out = { mapID = tonumber(mapID), x = tonumber(x) / 10000, y = tonumber(y) / 10000, campkeeper = false }
  local tag = text:match(TAG_PATTERN)
  if tag then
    out.campkeeper = true
    out.objects = {}
    for part in tag:gmatch("[^ ]+") do
      if part:match("^T%d$") then
        out.tier = tonumber(part:sub(2))
      elseif part:match("^%d+m$") then
        out.minutes = tonumber(part:sub(1, -2))
      elseif part:match("^#[0-9a-z]+$") then
        out.objects = decode(part:sub(2))
      end
    end
  end
  return out
end

-- At most one announcement of a camp per channel every INTERVAL seconds (kept in memory only).
local last = {}

-- true, or false and the seconds to wait.
function Announce:CanAnnounce(campID, channel, now)
  local at = last[campID .. "\0" .. channel]
  if at and now - at < self.INTERVAL then return false, self.INTERVAL - (now - at) end
  return true
end

function Announce:MarkAnnounced(campID, channel, now)
  last[campID .. "\0" .. channel] = now
end

-- The camp the player stands at: the most trusted known camp within CAMP_RANGE (the own fire
-- first), otherwise the player's position with nothing known about the camp. nil away from a
-- campfire: a stored record without the "Campfire Nearby" aura is a fire that has gone out.
function Announce:CurrentCamp()
  if not ns.CampState:Info().near then return nil end
  local pos = ns.api.playerPosition()
  if not pos or not pos.x then return nil end
  local best, bestRank, bestDistance
  for _, r in ipairs(ns.CampStore:All()) do
    local d = ns.CampStore:Distance(pos, r)
    if d and d <= self.CAMP_RANGE then
      local rank = ns.CampStore.RANK[r.source] or 0
      if not best or rank > bestRank or (rank == bestRank and d < bestDistance) then
        best, bestRank, bestDistance = r, rank, d
      end
    end
  end
  if best then return best end
  return { id = ("here-%d-%d-%d"):format(pos.mapID, round(pos.x * 1000), round(pos.y * 1000)),
           mapID = pos.mapID, x = pos.x, y = pos.y, objects = {} }
end

-- Chats the player can announce in right now, in the order of the default choice:
-- { key = "group"|"guild"|"general", chatType, target? }.
function Announce:Channels()
  local out = {}
  if IsInRaid() then
    out[#out + 1] = { key = "group", chatType = "RAID" }
  elseif IsInGroup() then
    out[#out + 1] = { key = "group", chatType = "PARTY" }
  end
  if IsInGuild() then out[#out + 1] = { key = "guild", chatType = "GUILD" } end
  local general = C_ChatInfo and C_ChatInfo.GetGeneralChannelLocalID
                  and Util.safeCall("GetGeneralChannelLocalID", C_ChatInfo.GetGeneralChannelLocalID)
  if general then out[#out + 1] = { key = "general", chatType = "CHANNEL", target = general } end
  return out
end

-- The language the player chose for announcements: "client" (default), "enUS" or "ruRU".
function Announce:Language()
  local a = ns.db.profile.announce
  return a and a.language or "client"
end

-- Announce the current camp in a chat (the first available one without a key). Sent straight
-- from the player's click or command: public channels accept messages only from a hardware
-- event, which a throttling library would lose. Returns true, or false and the reason to show.
function Announce:Send(key)
  local camp = self:CurrentCamp()
  if not camp then return false, L["You are not at a camp."] end
  local channel
  for _, c in ipairs(self:Channels()) do
    if not key or c.key == key then channel = c; break end
  end
  if not channel then return false, L["That chat is not available right now."] end
  local now = ns.api.serverTime()
  local ok, wait = self:CanAnnounce(camp.id, channel.key, now)
  if not ok then
    return false, L["This camp is already announced in that chat. Wait %s."]:format(Util.formatDuration(wait))
  end
  local text = self:Build(camp, now, self:Language())
  SendChatMessage(text, channel.chatType, nil, channel.target)
  self:MarkAnnounced(camp.id, channel.key, now)
  self:Expect(channel, text)
  if not camp.tier and not next(camp.objects or {}) then
    -- someone else's camp before the benefits: the line carries only the place
    ns.addon:Print(L["Nothing is known about this camp yet: sit by the fire and the announcement will list what it has."])
  end
  return true
end

-- Did the announcement reach the chat? The client gives no answer to a refused message, so the
-- own line coming back from the chat is the only proof. Both outcomes go to the debug log
-- (`/ck debug`); a line that never came back is also told to the player.
local pending = {}

function Announce:Expect(channel, text)
  ns.log("announce", "sent to %s (%s %s), %d bytes", channel.key, channel.chatType, tostring(channel.target or "-"), #text)
  local entry = { key = channel.key }
  pending[#pending + 1] = entry
  ns.api.after(self.CONFIRM_WAIT, function()
    if entry.seen then return end
    for i, e in ipairs(pending) do
      if e == entry then table.remove(pending, i); break end
    end
    ns.log("announce", "not seen in chat after %d s: %s", self.CONFIRM_WAIT, entry.key)
    ns.addon:Print(L["The announcement did not appear in chat: the game may not have let it through."])
  end)
end

-- A chat line written by the player (called for every own message the addon sees).
function Announce:OnOwnMessage(text)
  if #pending == 0 or not text:find("(" .. self.TAG, 1, true) then return end
  local entry = table.remove(pending, 1)
  entry.seen = true
  ns.log("announce", "seen in chat: %s", entry.key)
end
