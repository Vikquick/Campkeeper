local ADDON_NAME, ns = ...
local L = ns.L

-- Beta research: answers to the open client questions, collected while playing and kept only in
-- CampkeeperDB.global.research (never sent anywhere). `/ck report` prints a summary.
--   q1        raw "Camp Benefits" tooltip lines next to the parsed composition and own camp
--   q2        distance to the own campfire when "Campfire Nearby" appears / disappears
--   q3        new player auras while at a camp (Boosted Rest candidates, tent flagged)
--   q4        blueprints in the bags that mention camp objects, learned or not
--   q5        addon messages sent / echoed back / received from others, per distribution
--   blocked   ADDON_ACTION_BLOCKED / _FORBIDDEN for Campkeeper
--   fire      seconds between placing the own fire and losing its aura next to it
--   durations distinct durations of the sitting and benefits auras
--   errors    UI errors that followed a placement attempt
--   catalog   catalog items and spells the client does not know
local Research = { MAX = 50, FIRE_OUT_RANGE = 8, CATALOG_DELAY = 5, BAG_DELAY = 1, RECIPE_CLASS = 9 }
ns.Research = Research

local Util = ns.Util

local function enabled() return ns.db and ns.db.profile.research ~= false end

local function store()
  local r = ns.db.global.research
  for _, key in ipairs({ "q1", "q2", "q3", "q4", "blocked", "fire", "errors" }) do r[key] = r[key] or {} end
  r.q5 = r.q5 or {}
  for _, key in ipairs({ "sent", "queued", "echo", "others", "senders" }) do r.q5[key] = r.q5[key] or {} end
  r.durations = r.durations or { sitting = {}, benefits = {} }
  return r
end

local function push(list, entry)
  list[#list + 1] = entry
  while #list > Research.MAX do table.remove(list, 1) end
end

local function inc(map, key) map[key] = (map[key] or 0) + 1 end

local function now() return ns.api.serverTime() end

local function round(v, step)
  step = step or 1
  return math.floor(v / step + 0.5) * step
end

local function ownCampDistance()
  local camp = ns.OwnCamp:Get()
  if not camp then return nil end
  return ns.api.distance(ns.api.playerPosition(), camp), camp
end

-- Q1 ----------------------------------------------------------------------------------------
function Research:OnBenefitsParsed(composition)
  if not enabled() or not composition or not composition.raw then return end
  local r = store()
  local joined = table.concat(composition.raw, "\n")
  local last = r.q1[#r.q1]
  if last and last.joined == joined then return end
  local parsed, unknown, own = {}, {}, {}
  for _, o in ipairs(composition.objects) do parsed[#parsed + 1] = ("%s:T%d"):format(o.key, o.tier) end
  for _, u in ipairs(composition.unknown) do unknown[#unknown + 1] = u.name end
  local d, camp = ownCampDistance()
  if camp and d and d <= ns.OwnCamp.ATTACH_RANGE then
    for key in pairs(camp.objects) do own[#own + 1] = ("%s:T%d"):format(key, ns.Catalog:Get(key).tier) end
    table.sort(own)
  end
  local lines = {}
  for i, line in ipairs(composition.raw) do lines[i] = line end
  push(r.q1, { t = now(), joined = joined, lines = lines, parsed = parsed, unknown = unknown, own = own })
end

-- Q2 and fire burn time ---------------------------------------------------------------------
function Research:OnNearChanged(near)
  if not enabled() then return end
  local d, camp = ownCampDistance()
  if not d then return end
  local r = store()
  push(r.q2, { t = now(), near = near, d = round(d, 0.1) })
  if not near and d <= self.FIRE_OUT_RANGE then
    push(r.fire, { t = now(), elapsed = now() - camp.placedAt, tier = camp.tier })
  end
end

-- Q3 ----------------------------------------------------------------------------------------
local function campAura(spellID)
  local a = ns.Catalog.auras
  return spellID == a.near or spellID == a.sitting or spellID == a.benefits
end

local function tentInBenefits()
  local b = ns.CampState:Info().benefits
  for _, o in ipairs(b and b.objects or {}) do
    if o.key == "camp_tent" or ns.Catalog:Replaces(o.key) == "camp_tent" then return true end
  end
  return false
end

function Research:OnUnitAura(updateInfo)
  if not enabled() or not updateInfo or not updateInfo.addedAuras then return end
  if ns.CampState:Get() == "AWAY" or ns.api.inCombat() then return end
  local r = store()
  for _, aura in ipairs(updateInfo.addedAuras) do
    if not (Util.isSecret(aura) or Util.isSecret(aura.spellId) or Util.isSecret(aura.name)) then
      local id = aura.spellId
      if type(id) == "number" and not campAura(id) then
        local e = r.q3[id]
        if not e then
          e = { name = aura.name, duration = aura.duration, first = now(), count = 0, state = ns.CampState:Get() }
          r.q3[id] = e
        end
        e.count = e.count + 1
        e.tent = e.tent or tentInBenefits()
      end
    end
  end
end

-- Durations ---------------------------------------------------------------------------------
function Research:OnStateChanged(new, info)
  if not enabled() then return end
  if new == "SITTING" and info.sittingExpires then
    inc(store().durations.sitting, round(info.sittingExpires - ns.api.now()))
  end
end

function Research:OnBenefitsGained(info)
  if enabled() and info.benefitsDuration then inc(store().durations.benefits, round(info.benefitsDuration)) end
end

-- Q4 ----------------------------------------------------------------------------------------
local campNames
local function campObjectNames()
  if not campNames then
    campNames = {}
    for _, o in ipairs(ns.Catalog:Objects()) do
      if o.tier > 1 then
        for _, n in ipairs(ns.Catalog:Names(o.key)) do campNames[#campNames + 1] = { name = Util.normalize(n), key = o.key } end
      end
    end
  end
  return campNames
end

local function bagLines(bag, slot)
  local data = Util.safeCall("C_TooltipInfo.GetBagItem", C_TooltipInfo and C_TooltipInfo.GetBagItem, bag, slot)
  local out = {}
  for _, line in ipairs(data and data.lines or {}) do
    if type(line.leftText) == "string" and not Util.isSecret(line.leftText) then out[#out + 1] = line.leftText end
  end
  return out
end

function Research:ScanBags()
  if not enabled() or not C_Container or not C_Container.GetContainerNumSlots then return end
  local r = store()
  r.q4other = r.q4other or {}
  for bag = 0, 5 do
    for slot = 1, (Util.safeCall("GetContainerNumSlots", C_Container.GetContainerNumSlots, bag) or 0) do
      local item = Util.safeCall("GetContainerItemID", C_Container.GetContainerItemID, bag, slot)
      if item and not r.q4other[item] then
        local classID = select(6, Util.safeCall("GetItemInfoInstant", C_Item.GetItemInfoInstant, item))
        if classID == self.RECIPE_CLASS then
          local lines = bagLines(bag, slot)
          local text = Util.normalize(table.concat(lines, "\n")) or ""
          local teaches
          for _, c in ipairs(campObjectNames()) do
            if c.name ~= "" and text:find(c.name, 1, true) then teaches = c.key; break end
          end
          if teaches then
            local known = false
            for _, line in ipairs(lines) do if ITEM_SPELL_KNOWN and line == ITEM_SPELL_KNOWN then known = true end end
            local e = r.q4[item]
            if not e then
              e = { name = lines[1], teaches = teaches, first = now(), mapID = (ns.api.playerPosition() or {}).mapID }
              r.q4[item] = e
            end
            e.known, e.lines = known, { unpack(lines, 1, math.min(#lines, 12)) }
          else
            r.q4other[item] = true
          end
        end
      end
    end
  end
end

-- Q5 ----------------------------------------------------------------------------------------
function Research:OnSent(distribution, queued)
  if not enabled() then return end
  local q5 = store().q5
  inc(q5.sent, distribution)
  if queued then inc(q5.queued, distribution) end
end

function Research:OnAddonMessage(prefix, distribution, sender)
  if not enabled() or prefix ~= ns.Protocol.PREFIX then return end
  local q5 = store().q5
  local name = Ambiguate and Ambiguate(sender, "none") or sender
  if name == UnitName("player") then
    inc(q5.echo, distribution)
  else
    inc(q5.others, distribution)
    q5.senders[name] = true
  end
end

-- Blocked actions and placement errors ------------------------------------------------------
function Research:OnActionBlocked(event, addon, func)
  if not enabled() or addon ~= ADDON_NAME then return end
  push(store().blocked, { t = now(), event = event, func = func, combat = InCombatLockdown() })
  ns.log("research", "%s: %s", event, tostring(func))
end

function Research:OnUIError(errorType, message, key)
  if enabled() then push(store().errors, { t = now(), type = errorType, message = message, key = key }) end
end

-- Catalog check -----------------------------------------------------------------------------
function Research:CheckCatalog()
  if not enabled() then return end
  local items, spells = {}, {}
  local function item(id)
    if not Util.safeCall("GetItemInfoInstant", C_Item and C_Item.GetItemInfoInstant, id) then items[#items + 1] = id end
  end
  local function spell(id)
    if id and C_Spell and C_Spell.DoesSpellExist and not Util.safeCall("DoesSpellExist", C_Spell.DoesSpellExist, id) then
      spells[#spells + 1] = id
    end
  end
  for _, o in ipairs(ns.Catalog:Objects()) do
    for _, id in ipairs(o.items) do item(id) end
    for _, id in ipairs(o.place) do spell(id) end
    spell(o.craft)
  end
  for _, f in ipairs(ns.Catalog:Fires()) do item(f.item); spell(f.place); spell(f.craft) end
  for _, id in pairs(ns.Catalog.auras) do spell(id) end
  store().catalog = { t = now(), build = select(2, GetBuildInfo()), missingItems = items, missingSpells = spells }
  if #items + #spells > 0 then
    ns.log("research", "catalog ids missing in this client: %d items, %d spells", #items, #spells)
  end
end

-- Summary -----------------------------------------------------------------------------------
local function keysJoined(map)
  local out = {}
  for k, v in pairs(map) do out[#out + 1] = type(v) == "number" and ("%s x%d"):format(k, v) or tostring(k) end
  table.sort(out)
  return #out > 0 and table.concat(out, ", ") or "-"
end

local function range(values)
  if #values == 0 then return "-" end
  table.sort(values)
  return values[1] == values[#values] and tostring(values[1]) or ("%s-%s"):format(values[1], values[#values])
end

-- Report lines (also used by tests).
function Research:Report()
  local r = store()
  local lines = {}
  local function add(fmt, ...) lines[#lines + 1] = L[fmt]:format(...) end

  local higher, unknown = {}, {}
  for _, e in ipairs(r.q1) do
    for _, p in ipairs(e.parsed) do if not p:find(":T1$") then higher[p] = true end end
    for _, u in ipairs(e.unknown) do unknown[u] = true end
  end
  add("Q1 benefits tooltips: %d; higher tiers seen: %s; unknown names: %s", #r.q1, keysJoined(higher), keysJoined(unknown))

  local enter, leave = {}, {}
  for _, e in ipairs(r.q2) do table.insert(e.near and enter or leave, e.d) end
  add("Q2 aura radius: appears at %s yd, disappears at %s yd (%d samples)", range(enter), range(leave), #r.q2)

  local tent, n3 = {}, 0
  for id, e in pairs(r.q3) do
    n3 = n3 + 1
    if e.tent then tent[#tent + 1] = ("%s (%d)"):format(tostring(e.name), id) end
  end
  table.sort(tent)
  add("Q3 auras gained at camps: %d; with a tent: %s", n3, #tent > 0 and table.concat(tent, ", ") or "-")

  local n4, known = 0, 0
  for _, e in pairs(r.q4) do n4 = n4 + 1; if e.known then known = known + 1 end end
  add("Q4 camp blueprints seen: %d (learned: %d)", n4, known)

  add("Q5 sent: %s; own echo: %s; from others: %s", keysJoined(r.q5.sent), keysJoined(r.q5.echo), keysJoined(r.q5.others))

  add("Blocked actions: %d", #r.blocked)
  local burn = {}
  for _, e in ipairs(r.fire) do burn[#burn + 1] = e.elapsed end
  add("Campfire burned: %s s", range(burn))
  add("Durations: sitting %s s; benefits %s s", keysJoined(r.durations.sitting), keysJoined(r.durations.benefits))
  local errs = {}
  for _, e in ipairs(r.errors) do inc(errs, ("%s %s"):format(tostring(e.type), tostring(e.message))) end
  add("Placement errors: %s", keysJoined(errs))
  local c = r.catalog
  if c then
    add("Catalog check (build %s): missing items %d, missing spells %d", tostring(c.build), #c.missingItems, #c.missingSpells)
  else
    add("Catalog check: not run yet")
  end
  return lines
end

function Research:Clear()
  wipe(ns.db.global.research)
  store()
end

function Research:AddOptions()
  ns.Options.table.args.general.args.research = {
    type = "toggle", width = "full", order = 10,
    name = L["Collect beta data for the developer"],
    desc = L["Stays on your computer in the saved variables; /ck report shows it."],
    get = function() return enabled() end,
    set = function(_, v) ns.db.profile.research = v end,
  }
end

function Research:Init()
  store()
  ns.RegisterCallback(self, "CAMP_BENEFITS_PARSED", function(_, composition) Research:OnBenefitsParsed(composition) end)
  ns.RegisterCallback(self, "CAMP_NEAR_CHANGED", function(_, near) Research:OnNearChanged(near) end)
  ns.RegisterCallback(self, "CAMP_STATE_CHANGED", function(_, _, new, info) Research:OnStateChanged(new, info) end)
  ns.RegisterCallback(self, "CAMP_BENEFITS_GAINED", function(_, _, info) Research:OnBenefitsGained(info) end)
  ns.RegisterCallback(self, "COMM_SENT", function(_, distribution, queued) Research:OnSent(distribution, queued) end)
  ns.RegisterCallback(self, "CAMP_UI_ERROR", function(_, errorType, message, key) Research:OnUIError(errorType, message, key) end)

  local pending
  local events = CreateFrame("Frame")
  for _, e in ipairs({ "CHAT_MSG_ADDON", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "BAG_UPDATE_DELAYED" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
      Research:OnAddonMessage(a, c, d)
    elseif event == "BAG_UPDATE_DELAYED" then
      if pending then return end
      pending = true
      ns.api.after(Research.BAG_DELAY, function() pending = false; Research:ScanBags() end)
    else
      Research:OnActionBlocked(event, a, b)
    end
  end)
  ns.api.after(self.CATALOG_DELAY, function() Research:CheckCatalog(); Research:ScanBags() end)
end
