local _, ns = ...
local L = ns.L
local Util = ns.Util

-- Known camps as pins on the world map and the minimap (HereBeDragons-Pins). Unconfirmed camps
-- are translucent; camps within 500 yd float on the minimap edge. Click sets a waypoint.
local Pins = { EDGE_RANGE = 500, REFRESH = 5, SIZE = 14, UNCONFIRMED_ALPHA = 0.5 }
ns.Pins = Pins

local HBDPins = LibStub("HereBeDragons-Pins-2.0")
local DEFAULT_ICON = "Interface\\Icons\\Spell_Fire_Fire"
local SOURCE = { self = "your camp", seen = "seen by you", party = "group", guild = "guild", channel = "shared channel" }

local pool, used = {}, {}

function Pins:Title(r)
  return r.tier and ns.Catalog:Name("fire" .. r.tier) or L["Camp"]
end

-- Tooltip content: { title, lines = { ... } } — kept separate from frames for tests.
function Pins:TooltipLines(r)
  local now = ns.api.serverTime()
  local lines = {}
  local names = {}
  for key in pairs(r.objects) do names[#names + 1] = ns.Catalog:Name(key) end
  table.sort(names)
  for _, n in ipairs(names) do lines[#lines + 1] = n end
  local since = r.placedAt or r.lastSeen
  lines[#lines + 1] = L["Age: %s"]:format(Util.formatDuration(now - since))
  if r.expiresAt then lines[#lines + 1] = L["Goes out in: %s"]:format(Util.formatDuration(r.expiresAt - now)) end
  lines[#lines + 1] = L["Source: %s"]:format(L[SOURCE[r.source]])
  if not r.confirmed then lines[#lines + 1] = L["Unconfirmed: reported by one player"] end
  lines[#lines + 1] = L["Click: set a waypoint"]
  return { title = self:Title(r), lines = lines }
end

-- Waypoint to a camp: TomTom when loaded, otherwise the built-in user waypoint (super-tracked).
function Pins:Waypoint(r)
  local title = self:Title(r)
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(r.mapID, r.x, r.y, { title = title, from = "Campkeeper" })
    return "tomtom"
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(r.mapID) then
    ns.log("map", "cannot set a waypoint on map %s", tostring(r.mapID))
    return nil
  end
  C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(r.mapID, r.x, r.y))
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  return "builtin"
end

local function acquire()
  local pin = table.remove(pool)
  if not pin then
    pin = CreateFrame("Button", nil, UIParent)
    pin:SetSize(Pins.SIZE, Pins.SIZE)
    pin.texture = pin:CreateTexture(nil, "OVERLAY")
    pin.texture:SetAllPoints()
    pin:SetScript("OnEnter", function(self)
      local t = Pins:TooltipLines(self.record)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(t.title)
      for _, line in ipairs(t.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
      GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pin:SetScript("OnClick", function(self) Pins:Waypoint(self.record) end)
  end
  used[#used + 1] = pin
  return pin
end

local function styled(pin, r)
  pin.record = r
  pin.texture:SetTexture((r.tier and ns.Catalog:Icon("fire" .. r.tier)) or DEFAULT_ICON)
  pin:SetAlpha(r.confirmed and 1 or Pins.UNCONFIRMED_ALPHA)
  return pin
end

function Pins:Refresh()
  HBDPins:RemoveAllWorldMapIcons(self)
  HBDPins:RemoveAllMinimapIcons(self)
  for i = #used, 1, -1 do
    local pin = table.remove(used, i)
    pin:Hide()
    pool[#pool + 1] = pin
  end
  local here = ns.api.playerPosition()
  self.shown = {}
  for _, r in ipairs(ns.CampStore:All()) do
    if r.mapID and r.x and r.y then
      HBDPins:AddWorldMapIconMap(self, styled(acquire(), r), r.mapID, r.x, r.y, HBD_PINS_WORLDMAP_SHOW_PARENT)
      local d = here and ns.api.distance(here, r)
      local floatOnEdge = d ~= nil and d <= self.EDGE_RANGE
      HBDPins:AddMinimapIconMap(self, styled(acquire(), r), r.mapID, r.x, r.y, false, floatOnEdge)
      self.shown[#self.shown + 1] = { id = r.id, floatOnEdge = floatOnEdge, alpha = r.confirmed and 1 or self.UNCONFIRMED_ALPHA }
    end
  end
end

function Pins:Init()
  local scheduled = false
  ns.RegisterCallback(self, "CAMPS_UPDATED", function()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function() scheduled = false; Pins:Refresh() end)
  end)
  self.ticker = C_Timer.NewTicker(self.REFRESH, function() Pins:Refresh() end)
  self:Refresh()
end
