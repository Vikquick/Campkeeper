local ADDON_NAME, ns = ...
local L = ns.L

-- Optional alerts, each fired at most once per occurrence:
--   near      a camp is nearby (AWAY -> NEAR), throttled
--   gained    camp benefits received (a fresh aura, not one restored after /reload)
--   ending    camp benefits end in 5 minutes
--   cooldown  the shared camping cooldown is ready
--   fire      your own campfire goes out in 1 minute
local Alerts = { NEAR_THROTTLE = 60, ENDING_BEFORE = 300, FIRE_BEFORE = 60, FRESH_AURA = 10 }
ns.Alerts = Alerts

Alerts.KINDS = { "near", "gained", "ending", "cooldown", "fire" }
local TEXT = {
  near = "A camp is nearby: sit by the fire for its benefits.",
  gained = "Camp benefits received.",
  ending = "Camp benefits end in 5 minutes.",
  cooldown = "Camping items are ready again.",
  fire = "Your campfire goes out in 1 minute.",
}
local LABEL = {
  near = "Camp nearby", gained = "Benefits received", ending = "Benefits ending soon",
  cooldown = "Camping cooldown ready", fire = "Own campfire going out",
}

local timers = {}
local lastNear

local function enabled(kind)
  local a = ns.db.profile.alerts
  return a and a[kind] ~= false
end

function Alerts:Show(kind)
  if not enabled(kind) then return end
  local text = L[TEXT[kind]]
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.82, b = 0 })
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
  ns.addon:Print(text)
  ns.callbacks:Fire("ALERT_SHOWN", kind)
end

-- One pending timer per kind; rescheduling replaces it. `at` is server time.
local function schedule(kind, at)
  if timers[kind] then timers[kind]:Cancel(); timers[kind] = nil end
  local delay = at - ns.api.serverTime()
  if delay <= 0 then return end
  timers[kind] = ns.api.timer(delay, function()
    timers[kind] = nil
    Alerts:Show(kind)
  end)
end

local function scheduleBenefits(info)
  if not info.benefitsExpires then return end
  local remaining = info.benefitsExpires - ns.api.now()
  schedule("ending", ns.api.serverTime() + remaining - Alerts.ENDING_BEFORE)
end

function Alerts:Init()
  ns.RegisterCallback(self, "CAMP_STATE_CHANGED", function(_, old, new)
    if old == "AWAY" and new == "NEAR" then
      local now = ns.api.now()
      if not lastNear or now - lastNear >= self.NEAR_THROTTLE then
        lastNear = now
        self:Show("near")
      end
    end
  end)
  ns.RegisterCallback(self, "CAMP_BENEFITS_GAINED", function(_, _, info)
    local remaining = info.benefitsExpires - ns.api.now()
    if info.benefitsDuration and remaining >= info.benefitsDuration - self.FRESH_AURA then
      self:Show("gained")
    end
    scheduleBenefits(info)
  end)
  ns.RegisterCallback(self, "CAMP_COOLDOWN_UPDATED", function(_, readyAt) schedule("cooldown", readyAt) end)
  ns.RegisterCallback(self, "OWN_CAMP_PLACED", function(_, camp) schedule("fire", camp.expiresAt - self.FIRE_BEFORE) end)

  -- state restored at login
  local c = ns.Professions:Char()
  if c.cooldownReadyAt then schedule("cooldown", c.cooldownReadyAt) end
  local camp = ns.OwnCamp:Get()
  if camp then schedule("fire", camp.expiresAt - self.FIRE_BEFORE) end
  scheduleBenefits(ns.CampState:Info())
end

-- Before Options:Register (OnInitialize).
function Alerts:AddOptions()
  local args = {}
  for i, kind in ipairs(self.KINDS) do
    args[kind] = {
      type = "toggle", name = L[LABEL[kind]], order = i, width = "full",
      get = function() return enabled(kind) end,
      set = function(_, v) ns.db.profile.alerts[kind] = v end,
    }
  end
  ns.Options:AddGroup("alerts", { type = "group", name = L["Alerts"], inline = true, args = args })
end

function Alerts:Pending(kind) return timers[kind] ~= nil end
