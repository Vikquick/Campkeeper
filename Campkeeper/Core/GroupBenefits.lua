local _, ns = ...
local L = ns.L

-- Who in the group has Camp Benefits. The client hides other players' auras in combat (and when
-- they are out of range), so a member is "has", "none" or "unknown", and in combat the last
-- result is kept instead of reading again.
local GroupBenefits = {}
ns.GroupBenefits = GroupBenefits

local cached

-- Unit tokens of the group, the player first when in a party.
function GroupBenefits:Units()
  local units = { "player" }
  if IsInRaid() then
    units = {}
    for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
  elseif IsInGroup() then
    for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
  end
  return units
end

-- { { name, unit, state = "has"|"none"|"unknown", remaining? = seconds } } in group order.
function GroupBenefits:Status()
  if cached and ns.api.inCombat() then return cached end
  local spellID, now, out = ns.Catalog.auras.benefits, ns.api.now(), {}
  for _, unit in ipairs(self:Units()) do
    local name = ns.api.unitFullName(unit)
    if name then
      local aura = ns.api.unitAura(unit, spellID)
      local m = { name = name, unit = unit, state = "unknown" }
      if aura == false then
        m.state = "none"
      elseif aura then
        m.state = "has"
        if aura.expirationTime and aura.expirationTime > 0 then
          m.remaining = math.max(0, math.floor(aura.expirationTime - now + 0.5))
        end
      end
      out[#out + 1] = m
    end
  end
  cached = out
  return out
end

-- Names by state: none, unknown, and whether anybody is known to have the benefits.
local function split(status)
  local none, unknown, has = {}, {}, false
  for _, m in ipairs(status) do
    if m.state == "none" then
      none[#none + 1] = m.name
    elseif m.state == "unknown" then
      unknown[#unknown + 1] = m.name
    else
      has = true
    end
  end
  return none, unknown, has
end

-- One line for group chat: who lacks the benefits (members with an unknown state are left out),
-- or that everybody has them. nil when nothing is known about anyone.
function GroupBenefits:ChatLine()
  local none, _, has = split(self:Status())
  if #none > 0 then return L["No camp benefits: %s"]:format(table.concat(none, ", ")) end
  if has then return L["Everyone has camp benefits."] end
  return nil
end

function GroupBenefits:PostToChat()
  local channel = IsInRaid() and "RAID" or IsInGroup() and "PARTY" or nil
  local line = self:ChatLine()
  if not channel or not line then return false end
  SendChatMessage(line, channel)
  return true
end

-- Lines for the player alone (ready check).
function GroupBenefits:SummaryLines()
  local none, unknown, has = split(self:Status())
  local lines = {}
  if #none > 0 then lines[#lines + 1] = L["No camp benefits: %s"]:format(table.concat(none, ", ")) end
  if #unknown > 0 then lines[#lines + 1] = L["Camp benefits unknown: %s"]:format(table.concat(unknown, ", ")) end
  if #none == 0 and #unknown == 0 and has then lines[#lines + 1] = L["Everyone has camp benefits."] end
  return lines
end

function GroupBenefits:Init()
  local events = CreateFrame("Frame")
  events:RegisterEvent("READY_CHECK")
  events:SetScript("OnEvent", function()
    if ns.db.profile.alerts.readyCheck == false or not IsInGroup() then return end
    for _, line in ipairs(GroupBenefits:SummaryLines()) do ns.addon:Print(line) end
  end)
end
