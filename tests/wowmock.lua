-- Minimal WoW client environment for running addon code in Lua 5.1 (lupa).
-- Globals stay strict (unknown names are nil) so missing API surfaces as test errors;
-- frames are permissive (unknown methods are no-ops) because UI code calls many of them.

Mock = { time = 1000, serverTime = 1760000000, inCombat = false, locale = "enUS",
         errors = {}, chat = {}, frames = {}, timers = {}, sent = {} }

------------------------------------------------------------------------
-- Lua dialect: WoW globals and 5.1 extensions
------------------------------------------------------------------------
local _xpcall = xpcall
function xpcall(f, handler, ...)
  local n, args = select("#", ...), { ... }
  return _xpcall(function() return f(unpack(args, 1, n)) end, handler)
end

local function defaultErrorHandler(msg)
  table.insert(Mock.errors, tostring(msg))
  return msg
end
local errorHandler = defaultErrorHandler
function geterrorhandler() return errorHandler end
function seterrorhandler(h) errorHandler = h end
function securecallfunction(f, ...)
  return select(2, xpcall(f, errorHandler, ...))
end
securecall = function(f, ...)
  if type(f) == "string" then f = _G[f] end
  return securecallfunction(f, ...)
end

strfind, strsub, strlen, strlower, strupper, strrep = string.find, string.sub, string.len, string.lower, string.upper, string.rep
strbyte, strchar, strmatch, gsub, format, strformat = string.byte, string.char, string.match, string.gsub, string.format, string.format
strgmatch, gmatch, strrev = string.gmatch, string.gmatch, string.reverse
tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
floor, ceil, abs, max, min, sqrt, random = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.random
mod = math.fmod
bit = bit or {
  band = function(a, b) local r, m = 0, 1
    while a > 0 and b > 0 do if a % 2 == 1 and b % 2 == 1 then r = r + m end a, b, m = floor(a / 2), floor(b / 2), m * 2 end
    return r end,
  bor = function(a, b) local r, m = 0, 1
    while a > 0 or b > 0 do if a % 2 == 1 or b % 2 == 1 then r = r + m end a, b, m = floor(a / 2), floor(b / 2), m * 2 end
    return r end,
  lshift = function(a, n) return a * 2 ^ n end,
  rshift = function(a, n) return floor(a / 2 ^ n) end,
}
date, time = os.date, os.time

function strtrim(s, chars)
  if chars then
    local p = "[" .. chars:gsub("[%^%]%-%%]", "%%%0") .. "]"
    return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", ""))
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function strsplit(delims, str, pieces)
  local out, n, start = {}, 0, 1
  local pat = "[" .. delims:gsub("[%^%]%-%%]", "%%%0") .. "]"
  pieces = pieces or 0
  while not (pieces > 0 and n == pieces - 1) do
    local s, e = string.find(str, pat, start)
    if not s then break end
    n = n + 1; out[n] = str:sub(start, s - 1); start = e + 1
  end
  n = n + 1; out[n] = str:sub(start)
  return unpack(out, 1, n)
end

function strlenutf8(s) local _, n = s:gsub("[^\128-\191]", ""); return n end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strconcat(...) return table.concat({ ... }) end
function tostringall(...)
  local n, t = select("#", ...), { ... }
  for i = 1, n do t[i] = tostring(t[i]) end
  return unpack(t, 1, n)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function CopyTable(t)
  local c = {}
  for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
  return c
end
function Mixin(obj, ...)
  for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do obj[k] = v end end
  return obj
end
function CreateFromMixins(...) return Mixin({}, ...) end
function issecretvalue(v) return Mock.secrets ~= nil and Mock.secrets[v] == true end
function hooksecurefunc(tbl, name, hook)
  if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
  local orig = tbl[name]
  assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(name))
  tbl[name] = function(...) local r = { orig(...) }; hook(...); return unpack(r) end
end

------------------------------------------------------------------------
-- Client info, time, combat
------------------------------------------------------------------------
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 1, 2, 5
WOW_PROJECT_WRATH_CLASSIC, WOW_PROJECT_CATACLYSM_CLASSIC, WOW_PROJECT_MISTS_CLASSIC = 11, 14, 19
WOW_PROJECT_CAMELOT = 18
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
LE_EXPANSION_LEVEL_CURRENT = 0
Enum = {}

function GetBuildInfo() return "1.60.1", "70245", "Oct 1 2026", 16001, "", " ", 16001 end
function GetLocale() return Mock.locale end
function GetTime() return Mock.time end
function GetTimePreciseSec() return Mock.time end
function GetServerTime() return Mock.serverTime end
function debugprofilestop() return Mock.time * 1000 end
function GetFramerate() return 60 end
function InCombatLockdown() return Mock.inCombat end
function IsLoggedIn() return Mock.loggedIn == true end
function GetCurrentRegion() return 3 end
function GetCurrentRegionName() return "EU" end
function GetRealmName() return "Realm" end
function GetNormalizedRealmName() return "Realm" end
function UnitName(unit) if unit == "player" then return "Tester", nil end end
UnitNameUnmodified = UnitName
function UnitGUID(unit) if unit == "player" then return "Player-1234-0ABCDEF1" end end
function UnitClass(unit) if unit == "player" then return "Warrior", "WARRIOR", 1 end end
function UnitRace(unit) if unit == "player" then return "Human", "Human", 1 end end
function UnitFactionGroup(unit) if unit == "player" then return "Alliance", "Alliance" end end
function UnitLevel(unit) if unit == "player" then return 60 end end
function UnitAffectingCombat(unit) return unit == "player" and Mock.inCombat end
Mock.cvars = { rotateMinimap = "0", minimapZoom = "0", minimapInsideZoom = "0" }
function GetCVar(name) return Mock.cvars[name] end
function GetCVarBool(name) return Mock.cvars[name] == "1" end
C_CVar = { GetCVar = GetCVar, GetCVarBool = GetCVarBool }

C_AddOns = {
  GetAddOnMetadata = function(_, field) if field == "Version" then return "dev" end end,
  IsAddOnLoaded = function(name) return Mock.loadedAddOns ~= nil and Mock.loadedAddOns[name] == true end,
  LoadAddOn = function() return false end,
  GetAddOnEnableState = function() return 0 end,
}
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
IsAddOnLoaded = C_AddOns.IsAddOnLoaded

------------------------------------------------------------------------
-- Timers on a virtual clock
------------------------------------------------------------------------
local function addTimer(delay, fn, iterations)
  local t = { at = Mock.time + delay, fn = fn, delay = delay, left = iterations, cancelled = false }
  function t:Cancel() self.cancelled = true end
  function t:IsCancelled() return self.cancelled end
  table.insert(Mock.timers, t)
  return t
end
C_Timer = {
  After = function(delay, fn) addTimer(delay, fn, 1) end,
  NewTimer = function(delay, fn) local t; t = addTimer(delay, function() fn(t) end, 1); return t end,
  NewTicker = function(delay, fn, n)
    local t; t = addTimer(delay, function() fn(t) end, n or math.huge); return t end,
}

-- Advance the clock, running due timers and OnUpdate scripts in order.
function Mock.Advance(seconds)
  local target = Mock.time + (seconds or 0)
  repeat
    local due
    for _, t in ipairs(Mock.timers) do
      if not t.cancelled and t.at <= target and (not due or t.at < due.at) then due = t end
    end
    if due then
      Mock.serverTime = Mock.serverTime + math.floor(due.at - Mock.time)
      Mock.time = math.max(Mock.time, due.at)
      due.left = due.left - 1
      if due.left > 0 then due.at = due.at + due.delay else due.cancelled = true end
      xpcall(due.fn, errorHandler)
    end
  until not due
  Mock.serverTime = Mock.serverTime + math.floor(target - Mock.time)
  Mock.time = target
  for i = #Mock.timers, 1, -1 do if Mock.timers[i].cancelled then table.remove(Mock.timers, i) end end
  for _, f in ipairs(Mock.frames) do
    local s = f.scripts.OnUpdate
    if s and f.shown then xpcall(s, errorHandler, f, seconds or 0) end
  end
end

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
-- Permissive object: callable no-op whose PascalCase members are again stubs. Unknown frame
-- methods (and template children such as frame.Text) resolve to these; lowercase keys are data
-- fields and stay nil.
local stubMT = {}
local function isApiName(k) return type(k) == "string" and k:match("^%u") ~= nil end
stubMT.__index = function(_, k) if isApiName(k) then return setmetatable({}, stubMT) end end
stubMT.__call = function() return nil end
Mock.Stub = function() return setmetatable({}, stubMT) end

local Region = {}
local regionMT = {
  __index = function(_, k)
    local m = Region[k]
    if m ~= nil then return m end
    if isApiName(k) then return Mock.Stub() end
  end,
}

local function newRegion(kind, name, parent)
  local r = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {},
                           unitEvents = {}, attributes = {}, shown = true, points = {} }, regionMT)
  if name then _G[name] = r end
  return r
end

function Region:GetName() return self.name end
function Region:GetParent() return self.parent end
function Region:SetParent(p) self.parent = p end
function Region:GetObjectType() return self.kind end
function Region:IsObjectType(k) return self.kind == k end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
  local old = self.scripts[name]
  self.scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Region:HasScript() return true end
function Region:RegisterEvent(e) self.events[e] = true end
function Region:RegisterUnitEvent(e, ...) self.events[e] = true; self.unitEvents[e] = { ... } end
function Region:UnregisterEvent(e) self.events[e] = nil end
function Region:IsEventRegistered(e) return self.events[e] == true end
function Region:RegisterAllEvents() self.allEvents = true end
function Region:UnregisterAllEvents() self.allEvents = nil; self.events = {} end
function Region:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Region:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown end
function Region:SetAttribute(k, v)
  if Mock.inCombat and self.protected then error("SetAttribute on protected frame in combat") end
  self.attributes[k] = v
end
function Region:GetAttribute(k) return self.attributes[k] end
function Region:SetText(t) self.text = t end
function Region:GetText() return self.text end
function Region:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function Region:GetWidth() return self.width or 0 end
function Region:GetHeight() return self.height or 0 end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:GetSize() return self.width or 0, self.height or 0 end
function Region:GetScale() return 1 end
function Region:GetEffectiveScale() return 1 end
function Region:GetAlpha() return self.alpha or 1 end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetFrameLevel() return self.level or 1 end
function Region:SetFrameLevel(l) self.level = l end
function Region:GetFrameStrata() return self.strata or "MEDIUM" end
function Region:GetNumPoints() return #self.points end
function Region:SetPoint(...) table.insert(self.points, { ... }) end
function Region:ClearAllPoints() self.points = {} end
function Region:GetPoint(i) local p = self.points[i or 1]; if p then return unpack(p) end end
function Region:GetCenter() return 0, 0 end
function Region:GetLeft() return 0 end
function Region:GetRight() return 0 end
function Region:GetTop() return 0 end
function Region:GetBottom() return 0 end
function Region:GetNumChildren() return 0 end
function Region:GetChildren() return end
function Region:GetRegions() return end
function Region:GetFontString() return self.fontString end
function Region:GetStringWidth() return 0 end
function Region:GetStringHeight() return 0 end
function Region:IsMouseOver() return false end
function Region:IsProtected() return self.protected == true end
function Region:CreateTexture(name) return newRegion("Texture", name, self) end
function Region:CreateMaskTexture(name) return newRegion("MaskTexture", name, self) end
function Region:CreateFontString(name)
  local fs = newRegion("FontString", name, self); self.fontString = self.fontString or fs; return fs
end
function Region:CreateLine(name) return newRegion("Line", name, self) end
function Region:CreateAnimationGroup(name) return newRegion("AnimationGroup", name, self) end
function Region:CreateAnimation(kind, name) return newRegion(kind or "Animation", name, self) end
function Region:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Region:GetTextColor() return 1, 1, 1, 1 end
function Region:GetVertexColor() return 1, 1, 1, 1 end
function Region:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function Region:GetNormalTexture() return self.normalTexture or newRegion("Texture", nil, self) end
function Region:GetHighlightTexture() return newRegion("Texture", nil, self) end
function Region:GetPushedTexture() return newRegion("Texture", nil, self) end
function Region:GetCheckedTexture() return newRegion("Texture", nil, self) end
function Region:GetDisabledTexture() return newRegion("Texture", nil, self) end
function Region:GetStatusBarTexture() return newRegion("Texture", nil, self) end
function Region:GetMinMaxValues() return 0, 1 end
function Region:GetValue() return self.value or 0 end
function Region:SetValue(v) self.value = v end
function Region:GetChecked() return self.checked end
function Region:SetChecked(v) self.checked = v end
function Region:IsEnabled() return self.enabled ~= false end
function Region:Enable() self.enabled = true end
function Region:Disable() self.enabled = false end
function Region:GetID() return self.id or 0 end
function Region:SetID(id) self.id = id end
function Region:GetNumLines() return 0 end
function Region:NumLines() return 0 end
function Region:GetHyperlinksEnabled() return false end
function Region:IsForbidden() return false end
function Region:CanChangeProtectedState() return not Mock.inCombat end
function Region:GetBoundsRect() return 0, 0, 0, 0 end
function Region:GetCursorPosition() return 0 end
function Region:GetMaxLetters() return 0 end
function Region:GetNumLetters() return 0 end
function Region:HasFocus() return false end
function Region:GetVerticalScroll() return 0 end
function Region:GetVerticalScrollRange() return 0 end
function Region:GetHorizontalScroll() return 0 end
function Region:GetScrollChild() return self.scrollChild end
function Region:SetScrollChild(c) self.scrollChild = c end
function Region:GetDuration() return 0 end

function CreateFrame(kind, name, parent, template)
  local f = newRegion(kind or "Frame", name, parent)
  f.template = template
  f.protected = template ~= nil and tostring(template):find("Secure") ~= nil
  table.insert(Mock.frames, f)
  return f
end

-- Deliver an event to every frame that registered it (or all events).
function Mock.Fire(event, ...)
  for _, f in ipairs(Mock.frames) do
    local s = f.scripts.OnEvent
    if s and (f.allEvents or f.events[event]) then xpcall(s, errorHandler, f, event, ...) end
  end
end

UIParent = CreateFrame("Frame", "UIParent")
WorldFrame = CreateFrame("Frame", "WorldFrame")
Minimap = CreateFrame("Minimap", "Minimap", UIParent)
function Minimap:GetZoom() return 0 end
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameFontNormal = newRegion("Font", "GameFontNormal")
GameFontHighlight = newRegion("Font", "GameFontHighlight")
GameFontHighlightSmall = newRegion("Font", "GameFontHighlightSmall")
GameFontNormalSmall = newRegion("Font", "GameFontNormalSmall")
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

------------------------------------------------------------------------
-- Maps: a tiny world. World X points north, Y points west (as in the client).
-- A map covers world X in [top - height, top] and Y in [left - width, left].
------------------------------------------------------------------------
Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
Mock.maps = {
  [946]  = { name = "Cosmic", mapType = 0, parentMapID = 0, instance = -1 },
  [947]  = { name = "Azeroth", mapType = 1, parentMapID = 946, instance = -1 },
  [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947, instance = 0,
             top = 18000, left = 10000, width = 20000, height = 30000 },
  [1429] = { name = "Elwynn Forest", mapType = 3, parentMapID = 1415, instance = 0,
             top = 0, left = 0, width = 3000, height = 2000 },
  [1453] = { name = "Stormwind City", mapType = 3, parentMapID = 1415, instance = 0,
             top = 1000, left = 1000, width = 1000, height = 700 },
}
Mock.player = { mapID = 1429, x = 0.5, y = 0.5, facing = 0 }

local Vector2DMixin = {}
function Vector2DMixin:GetXY() return self.x, self.y end
function CreateVector2D(x, y) return setmetatable({ x = x, y = y }, { __index = Vector2DMixin }) end

local function mapInfo(id)
  local m = Mock.maps[id]
  if m then return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID } end
end
-- World position (x north, y west) of a normalized map position.
function Mock.MapToWorld(id, mx, my)
  local m = Mock.maps[id]
  return m.top - my * m.height, m.left - mx * m.width, m.instance
end
C_Map = {
  GetMapInfo = mapInfo,
  GetBestMapForUnit = function(unit) if unit == "player" then return Mock.player.mapID end end,
  GetMapChildrenInfo = function(parent)
    local out = {}
    for id, m in pairs(Mock.maps) do if m.parentMapID == parent then table.insert(out, mapInfo(id)) end end
    table.sort(out, function(a, b) return a.mapID < b.mapID end)
    return out
  end,
  GetMapGroupID = function() return nil end,
  GetMapGroupMembersInfo = function() return nil end,
  GetMapWorldSize = function(id)
    local m = Mock.maps[id]
    if m and m.width then return m.width, m.height end
    return 0, 0
  end,
  GetWorldPosFromMapPos = function(id, pos)
    local m = Mock.maps[id]
    if not m or not m.width then return m and m.instance or -1, nil end
    local x, y = Mock.MapToWorld(id, pos.x, pos.y)
    return m.instance, CreateVector2D(x, y)
  end,
  GetMapRectOnMap = function() return nil end,
  GetPlayerMapPosition = function(id, unit)
    if unit == "player" and id == Mock.player.mapID then return CreateVector2D(Mock.player.x, Mock.player.y) end
  end,
  SetUserWaypoint = function(point) Mock.waypoint = point end,
  ClearUserWaypoint = function() Mock.waypoint = nil end,
  HasUserWaypoint = function() return Mock.waypoint ~= nil end,
  CanSetUserWaypointOnMap = function() return true end,
}
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, position = CreateVector2D(x, y) } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) Mock.superTracked = v end }
function UnitPosition(unit)
  if unit ~= "player" then return nil end
  local p = Mock.player
  local x, y, instance = Mock.MapToWorld(p.mapID, p.x, p.y)
  return y, x, 0, instance -- the client returns (y, x, z, instance) — HBD swaps accordingly
end
function GetPlayerFacing() return Mock.player.facing end
C_Minimap = { GetViewRadius = function() return 200 end }
function GetMinimapShape() return "ROUND" end
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.pinPools = {}
function WorldMapFrame:GetMapID() return Mock.player.mapID end
function WorldMapFrame:EnumeratePinsByTemplate() return function() return nil end end
MapCanvasDataProviderMixin = { GetMap = function() return WorldMapFrame end }
MapCanvasPinMixin = {}
function CreateFramePool() return Mock.Stub() end
function CreateUnsecuredRegionPoolInstance() return Mock.Stub() end

------------------------------------------------------------------------
-- Item and spell data: entries in Mock.items / Mock.spells are "cached" unless loaded == false;
-- Mock.LoadItem / Mock.LoadSpell finish a pending load and fire the client event.
------------------------------------------------------------------------
Mock.items, Mock.spells, Mock.requested = {}, {}, { items = {}, spells = {} }
local function cached(t, id) local e = t[id]; return e and e.loaded ~= false and e or nil end
C_Item = {
  GetItemNameByID = function(id) local e = cached(Mock.items, id); return e and e.name end,
  GetItemIconByID = function(id) local e = Mock.items[id]; return e and e.icon or 134400 end,
  IsItemDataCachedByID = function(id) return cached(Mock.items, id) ~= nil end,
  RequestLoadItemDataByID = function(id) Mock.requested.items[id] = true end,
}
C_Spell = {
  GetSpellName = function(id) local e = cached(Mock.spells, id); return e and e.name end,
  GetSpellDescription = function(id) local e = cached(Mock.spells, id); return e and e.description or "" end,
  GetSpellTexture = function(id) local e = Mock.spells[id]; return e and e.icon or 136243 end,
  RequestLoadSpellData = function(id) Mock.requested.spells[id] = true end,
}
function Mock.LoadItem(id, success)
  if Mock.items[id] then Mock.items[id].loaded = true end
  Mock.Fire("ITEM_DATA_LOAD_RESULT", id, success ~= false)
end
function Mock.LoadSpell(id, success)
  if Mock.spells[id] then Mock.spells[id].loaded = true end
  Mock.Fire("SPELL_DATA_LOAD_RESULT", id, success ~= false)
end

------------------------------------------------------------------------
-- Player auras and their tooltips. Mock.AddAura/RefreshAura/RemoveAura fire UNIT_AURA with an
-- updateInfo like the client's. Mock.secretAuras makes aura reads return secret values.
------------------------------------------------------------------------
Mock.auras, Mock.tooltips = {}, {}
local nextAuraInstance = 1000
-- A value issecretvalue() reports as secret (only tables can be marked in the mock).
function Mock.Secret()
  local s = {}
  Mock.secrets = Mock.secrets or {}
  Mock.secrets[s] = true
  return s
end
local function auraCopy(a)
  if Mock.secretAuras then
    return { auraInstanceID = Mock.Secret(), spellId = Mock.Secret(), name = Mock.Secret(),
             expirationTime = Mock.Secret(), duration = Mock.Secret() }
  end
  return { auraInstanceID = a.auraInstanceID, spellId = a.spellId, name = a.name,
           expirationTime = a.expirationTime, duration = a.duration, isHelpful = true }
end
C_UnitAuras = {
  GetPlayerAuraBySpellID = function(spellID)
    for _, a in pairs(Mock.auras) do if a.spellId == spellID then return auraCopy(a) end end
  end,
  GetAuraDataByAuraInstanceID = function(unit, id)
    local a = unit == "player" and Mock.auras[id]
    return a and auraCopy(a) or nil
  end,
}
function Mock.AddAura(spellId, duration, name)
  nextAuraInstance = nextAuraInstance + 1
  local a = { auraInstanceID = nextAuraInstance, spellId = spellId, name = name or ("aura" .. spellId),
              duration = duration or 0, expirationTime = (duration and duration > 0) and (Mock.time + duration) or 0 }
  Mock.auras[a.auraInstanceID] = a
  Mock.Fire("UNIT_AURA", "player", { addedAuras = { auraCopy(a) } })
  return a.auraInstanceID
end
function Mock.RefreshAura(id, duration)
  local a = Mock.auras[id]
  a.duration = duration or a.duration
  a.expirationTime = Mock.time + a.duration
  Mock.Fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { id } })
end
function Mock.RemoveAura(id)
  Mock.auras[id] = nil
  Mock.tooltips[id] = nil
  Mock.Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { id } })
end
function Mock.AuraID(spellId)
  for id, a in pairs(Mock.auras) do if a.spellId == spellId then return id end end
end
C_TooltipInfo = {
  GetUnitBuffByAuraInstanceID = function(unit, id)
    local t = unit == "player" and Mock.tooltips[id]
    if not t then return nil end
    local lines = {}
    for i, text in ipairs(t) do lines[i] = { leftText = text } end
    return { type = 7, lines = lines }
  end,
}

------------------------------------------------------------------------
-- SavedVariables writer (for relog tests)
------------------------------------------------------------------------
function Mock.Serialize(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  local out = {}
  for k, val in pairs(v) do
    local key = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
    out[#out + 1] = key .. " = " .. Mock.Serialize(val)
  end
  return "{ " .. table.concat(out, ", ") .. " }"
end

------------------------------------------------------------------------
-- Professions, bags, item cooldowns, casts
------------------------------------------------------------------------
Mock.professions = {} -- list of { skillLine, rank, max, name } in GetProfessions slot order
Mock.bags, Mock.knownSpells, Mock.recipes = {}, {}, {}
Mock.itemCooldown = { start = 0, duration = 0 }
function GetProfessions()
  local idx = {}
  for i = 1, #Mock.professions do idx[i] = i end
  return unpack(idx, 1, 6)
end
function GetProfessionInfo(i)
  local p = Mock.professions[i]
  if p then return p.name or "prof", 0, p.rank, p.max or 300, 0, 0, p.skillLine end
end
C_Item.GetItemCount = function(id) return Mock.bags[id] or 0 end
C_Container = {
  GetItemCooldown = function() return Mock.itemCooldown.start, Mock.itemCooldown.duration, 1 end,
}
function IsPlayerSpell(id) return Mock.knownSpells[id] == true end
C_TradeSkillUI = {
  GetRecipeInfo = function(id) local r = Mock.recipes[id]; if r ~= nil then return { recipeID = id, learned = r } end end,
}
function Mock.Cast(spellID)
  Mock.Fire("UNIT_SPELLCAST_SENT", "player", "", "Cast-1", spellID)
  Mock.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", spellID)
end

-- Alerts
Mock.raidNotices, Mock.sounds = {}, {}
RaidWarningFrame = CreateFrame("Frame", "RaidWarningFrame", UIParent)
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 0.3, b = 0.1 } }
function RaidNotice_AddMessage(_, text) table.insert(Mock.raidNotices, text) end
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(id) table.insert(Mock.sounds, id) end

------------------------------------------------------------------------
-- Settings panel (AceConfigDialog:AddToBlizOptions)
------------------------------------------------------------------------
Mock.settings = {}
local nextCategoryID = 100
local function newCategory(frame, name, parent)
  nextCategoryID = nextCategoryID + 1
  local c = { ID = nextCategoryID, name = name, frame = frame, parent = parent }
  function c:GetID() return self.ID end
  function c:GetName() return self.name end
  Mock.settings[c.ID] = c
  return c
end
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name) return newCategory(frame, name) end,
  RegisterCanvasLayoutSubcategory = function(parent, frame, name) return newCategory(frame, name, parent) end,
  RegisterAddOnCategory = function(c) c.registered = true end,
  GetCategory = function(id)
    for _, c in pairs(Mock.settings) do if c.ID == id or c.name == id then return c end end
  end,
  OpenToCategory = function(id) Mock.openedCategory = id end,
}
C_SettingsUtil = { OpenSettingsPanel = function(id) Mock.openedCategory = id end }

------------------------------------------------------------------------
-- Chat, slash commands, addon messages
------------------------------------------------------------------------
SlashCmdList, hash_SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = CreateFrame("ScrollingMessageFrame", "ChatFrame1", UIParent)
function DEFAULT_CHAT_FRAME:AddMessage(msg) table.insert(Mock.chat, tostring(msg)) end
SELECTED_CHAT_FRAME = DEFAULT_CHAT_FRAME
NUM_CHAT_WINDOWS = 1
function ChatFrame_AddMessageEventFilter() end
function ChatFrame_RemoveMessageEventFilter() end
function ChatFrame_RemoveChannel() end
function SendChatMessage(msg, chatType, _, target)
  table.insert(Mock.sent, { kind = "chat", msg = msg, chatType = chatType, target = target })
end

-- Run a slash command line such as "/ck debug".
function Mock.Slash(line)
  local cmd, rest = line:match("^(/%S+)%s*(.-)$")
  cmd = cmd:upper()
  for key, fn in pairs(SlashCmdList) do
    local i = 1
    while _G["SLASH_" .. key .. i] do
      if _G["SLASH_" .. key .. i]:upper() == cmd then return fn(rest, DEFAULT_CHAT_FRAME) end
      i = i + 1
    end
  end
  error("unknown slash command " .. cmd)
end

local prefixes = {}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) prefixes[p] = true; return true end,
  IsAddonMessagePrefixRegistered = function(p) return prefixes[p] == true end,
  SendAddonMessage = function(prefix, msg, chatType, target)
    table.insert(Mock.sent, { kind = "addon", prefix = prefix, msg = msg, chatType = chatType, target = target })
    return true
  end,
  SendAddonMessageLogged = function(prefix, msg, chatType, target)
    return C_ChatInfo.SendAddonMessage(prefix, msg, chatType, target)
  end,
  InChatMessagingLockdown = function() return Mock.chatLockdown == true end,
  AreOutgoingAddonChatMessagesRestricted = function() return Mock.addonRestricted == true end,
}
Enum.SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, GeneralError = 9 }
function BNSendGameData() end
C_BattleNet = {}
function GetChannelName() return 0 end
function JoinTemporaryChannel() end
function LeaveChannelByName() end
function IsInGroup() return Mock.inGroup == true end
function IsInRaid() return Mock.inRaid == true end
function IsInGuild() return Mock.inGuild == true end
function IsInInstance() return false, "none" end
function GetNumGroupMembers() return 0 end
