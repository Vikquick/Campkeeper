local _, ns = ...

-- Reads the composition of the "Camp Benefits" aura from its tooltip. The aura's numeric points
-- do not match the text, so the tooltip is the source. Observed in the client (ruRU):
--   [1] "Бонусы лагеря"
--   [2] "Получены следующие бонусы лагеря:\r\n\r\nМагнетит: сила атаки ближнего боя повышена на 20.\r\n\r\n"
--   [3] "Осталось 60 |4минута:минуты:минут;"
-- Line [2] arrives about half a second after the aura, so parsing retries until at least one
-- "<Object>: <effect>" line is present. Names are matched against every client name of every
-- object (item and placement spell, all tiers). Unknown lines are kept and logged.
local BenefitsParser = { RETRIES = 5, RETRY_DELAY = 1 }
ns.BenefitsParser = BenefitsParser

local Util = ns.Util

local function nameIndex()
  local index = {}
  for _, o in ipairs(ns.Catalog:Objects()) do
    for _, name in ipairs(ns.Catalog:Names(o.key)) do
      local n = Util.normalize(name)
      -- several tiers can share a name only if the client reuses it; keep the higher tier
      if n and (not index[n] or index[n].tier < o.tier) then index[n] = o end
    end
  end
  return index
end

-- Remove colour, texture and grammar (|4singular:plural;) escape codes.
local function plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|4[^;]*;", ""))
end

-- Split "Name: effect". Returns nil for headers ("...:" with no effect) and other lines.
local function splitLine(line)
  local name, effect = plain(line):match("^%s*(.-)%s*:%s*(.-)%s*$")
  if not name or name == "" or effect == "" then return nil end
  return name, effect
end

-- Tooltip lines (header first; lines may contain embedded newlines) -> { objects, unknown }.
function BenefitsParser:ParseLines(lines)
  local index = nameIndex()
  local result = { objects = {}, unknown = {} }
  for i = 2, #lines do
    for line in (lines[i] .. "\n"):gmatch("(.-)\r?\n") do
      local name, effect = splitLine(line)
      if name then
        local o = index[Util.normalize(name)]
        if o then
          table.insert(result.objects, { key = o.key, tier = o.tier, name = name, effect = effect })
        else
          table.insert(result.unknown, { name = name, effect = effect })
          ns.log("benefits", "unknown line: %s", line)
        end
      end
    end
  end
  return result
end

-- Read and parse the aura tooltip, retrying while the client has not filled it in yet.
-- Calls done(composition); composition is nil when no object line appeared after all retries.
function BenefitsParser:Parse(auraInstanceID, done, attempt)
  attempt = attempt or 1
  local lines = ns.api.buffTooltipLines(auraInstanceID)
  if lines then
    local result = self:ParseLines(lines)
    if #result.objects + #result.unknown > 0 then return done(result) end
  end
  if attempt >= self.RETRIES then
    ns.log("benefits", "no camp objects in tooltip of aura %s after %d attempts", tostring(auraInstanceID), attempt)
    return done(nil)
  end
  ns.api.after(self.RETRY_DELAY, function() self:Parse(auraInstanceID, done, attempt + 1) end)
end
