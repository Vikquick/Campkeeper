-- Camp probe: records what the client exposes around campsites
-- (auras with tooltip text, own casts, vignettes, hovered objects, soft-interact
-- targets and every event that fires) into ForeverApiDumpDB.camp.
-- Usage: /fad camp start, play at a camp, /fad camp stop, /reload.

local _, ns = ...

local MAX_ENTRIES = 6000
local EVENT_SAMPLES = 5     -- payload samples kept per ordinary event
local VIGNETTE_POLL = 2     -- seconds

-- Events logged on every occurrence, not just the first samples
local ALWAYS_LOG = {
	PLAYER_CAMPING = true,
	CHAT_MSG_SYSTEM = true,
	UI_INFO_MESSAGE = true,
	UI_ERROR_MESSAGE = true,
	PLAYER_SOFT_INTERACT_CHANGED = true,
	PLAYER_UPDATE_RESTING = true,
	UPDATE_EXHAUSTION = true,
}

-- High-volume events that tell us nothing about camps
local IGNORE = {
	COMBAT_LOG_EVENT_UNFILTERED = true,
	UNIT_POWER_UPDATE = true,
	UNIT_POWER_FREQUENT = true,
	UNIT_HEALTH = true,
	UNIT_AURA = true, -- handled separately
	ACTIONBAR_UPDATE_COOLDOWN = true,
	SPELL_UPDATE_COOLDOWN = true,
	SPELL_UPDATE_USABLE = true,
	CURSOR_CHANGED = true,
	UPDATE_MOUSEOVER_UNIT = true,
	MODIFIER_STATE_CHANGED = true,
	NAME_PLATE_UNIT_ADDED = true,
	NAME_PLATE_UNIT_REMOVED = true,
	UNIT_THREAT_LIST_UPDATE = true,
	CHAT_MSG_ADDON = true,
	CHAT_MSG_CHANNEL = true,
	WORLD_CURSOR_TOOLTIP_UPDATE = true,
}

local probe = CreateFrame("Frame")
local active = false
local eventSamples = {}
local knownVignettes = {}
local lastTooltipKey, lastTooltipAt
local ticker

local function db()
	ForeverApiDumpDB.camp = ForeverApiDumpDB.camp or { log = {} }
	return ForeverApiDumpDB.camp
end

local function position()
	local mapID = ns.safeCall(C_Map.GetBestMapForUnit, "player")
	local pos = { mapID = mapID }
	if mapID then
		local v = ns.safeCall(C_Map.GetPlayerMapPosition, mapID, "player")
		if v and v.GetXY then
			pos.x, pos.y = v:GetXY()
		end
	end
	pos.wy, pos.wx, pos.wz, pos.instance = ns.safeCall(UnitPosition, "player")
	return pos
end

local function record(kind, data)
	local log = db().log
	if #log >= MAX_ENTRIES then
		if active then
			active = false
			probe:UnregisterAllEvents()
			ns.say("camp log is full (%d entries), probe stopped", MAX_ENTRIES)
		end
		return
	end
	data = ns.deepCopy(data or {})
	data.kind = kind
	data.t = GetTime()
	data.clock = date("%H:%M:%S")
	data.pos = position()
	log[#log + 1] = data
end

local function tooltipLines(tooltipData)
	if type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then return nil end
	local lines = {}
	for i, line in ipairs(tooltipData.lines) do
		local left = line.leftText
		local right = line.rightText
		if ns.isSecret(left) then left = "<secret>" end
		if ns.isSecret(right) then right = "<secret>" end
		lines[i] = right and right ~= "" and (tostring(left) .. " | " .. tostring(right)) or tostring(left)
	end
	return lines
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------

local function auraTooltip(aura)
	local fn = aura.isHelpful and C_TooltipInfo.GetUnitBuffByAuraInstanceID
		or C_TooltipInfo.GetUnitDebuffByAuraInstanceID
	return tooltipLines(ns.safeCall(fn, "player", aura.auraInstanceID))
end

local function recordAura(kind, aura)
	if type(aura) ~= "table" then return end
	record(kind, {
		auraInstanceID = aura.auraInstanceID,
		spellId = aura.spellId,
		name = aura.name,
		icon = aura.icon,
		isHelpful = aura.isHelpful,
		duration = aura.duration,
		expirationTime = aura.expirationTime,
		applications = aura.applications,
		sourceUnit = aura.sourceUnit,
		points = aura.points,
		tooltip = auraTooltip(aura),
	})
end

local function snapshotAuras()
	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		for i = 1, 80 do
			local aura = ns.safeCall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
			if not aura then break end
			recordAura("aura_snapshot", aura)
		end
	end
end

local function onUnitAura(unit, info)
	if unit ~= "player" then return end
	if not info or info.isFullUpdate then
		record("aura_full_update")
		snapshotAuras()
		return
	end
	for _, aura in ipairs(info.addedAuras or {}) do
		recordAura("aura_added", aura)
	end
	for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
		recordAura("aura_updated", ns.safeCall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id))
	end
	for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
		record("aura_removed", { auraInstanceID = id })
	end
end

---------------------------------------------------------------------------
-- Casts
---------------------------------------------------------------------------

local function spellName(spellID)
	local info = ns.safeCall(C_Spell.GetSpellInfo, spellID)
	return info and info.name
end

local CAST_EVENTS = {
	UNIT_SPELLCAST_SENT = function(unit, target, castGUID, spellID)
		return { unit = unit, target = target, castGUID = castGUID, spellID = spellID }
	end,
	UNIT_SPELLCAST_START = function(unit, castGUID, spellID)
		return { unit = unit, castGUID = castGUID, spellID = spellID }
	end,
	UNIT_SPELLCAST_SUCCEEDED = function(unit, castGUID, spellID)
		return { unit = unit, castGUID = castGUID, spellID = spellID }
	end,
	UNIT_SPELLCAST_CHANNEL_START = function(unit, castGUID, spellID)
		return { unit = unit, castGUID = castGUID, spellID = spellID }
	end,
	UNIT_SPELLCAST_FAILED = function(unit, castGUID, spellID)
		return { unit = unit, castGUID = castGUID, spellID = spellID }
	end,
}

---------------------------------------------------------------------------
-- Vignettes (minimap points of interest)
---------------------------------------------------------------------------

local function pollVignettes()
	if not active or not C_VignetteInfo then return end
	local mapID = ns.safeCall(C_Map.GetBestMapForUnit, "player")
	local seen = {}
	for _, guid in ipairs(ns.safeCall(C_VignetteInfo.GetVignettes) or {}) do
		seen[guid] = true
		if not knownVignettes[guid] then
			knownVignettes[guid] = true
			local info = ns.safeCall(C_VignetteInfo.GetVignetteInfo, guid)
			local vpos = mapID and ns.safeCall(C_VignetteInfo.GetVignettePosition, guid, mapID)
			local vx, vy
			if vpos and vpos.GetXY then vx, vy = vpos:GetXY() end
			record("vignette_added", { guid = guid, info = info, vx = vx, vy = vy })
		end
	end
	for guid in pairs(knownVignettes) do
		if not seen[guid] then
			knownVignettes[guid] = nil
			record("vignette_removed", { guid = guid })
		end
	end
end

---------------------------------------------------------------------------
-- Tooltips (hovered world objects, bag items, spells)
---------------------------------------------------------------------------

local function onTooltip(tooltip, data)
	if not active or type(data) ~= "table" then return end
	local lines = tooltipLines(data)
	local key = tostring(data.type) .. ":" .. tostring(data.id) .. ":" .. tostring(lines and lines[1])
	local now = GetTime()
	if key == lastTooltipKey and now - (lastTooltipAt or 0) < 5 then return end
	lastTooltipKey, lastTooltipAt = key, now
	record("tooltip", {
		tooltip = tooltip and tooltip.GetName and tooltip:GetName(),
		type = data.type,
		id = data.id,
		guid = data.guid,
		lines = lines,
	})
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, onTooltip)
end

---------------------------------------------------------------------------
-- Generic event capture
---------------------------------------------------------------------------

local function packArgs(...)
	local args = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if ns.isSecret(v) then
			args[i] = "<secret>"
		elseif type(v) == "table" or type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
			args[i] = v
		else
			args[i] = "<" .. type(v) .. ">"
		end
	end
	return args
end

probe:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_AURA" then
		onUnitAura(...)
		return
	end
	local cast = CAST_EVENTS[event]
	if cast then
		if ... == "player" then
			local data = cast(...)
			data.event = event
			data.name = spellName(data.spellID)
			record("cast", data)
		end
		return
	end
	if event == "VIGNETTES_UPDATED" or event == "VIGNETTE_MINIMAP_UPDATED" then
		pollVignettes()
	end
	if event == "PLAYER_SOFT_INTERACT_CHANGED" then
		record("soft_interact", {
			args = packArgs(...),
			name = ns.safeCall(UnitName, "softinteract"),
			guid = ns.safeCall(UnitGUID, "softinteract"),
		})
		return
	end
	if IGNORE[event] then return end
	local n = (eventSamples[event] or 0) + 1
	eventSamples[event] = n
	if ALWAYS_LOG[event] or event:find("CAMP") or n <= EVENT_SAMPLES then
		record("event", { event = event, n = n, args = packArgs(...) })
	end
end)

---------------------------------------------------------------------------
-- Control
---------------------------------------------------------------------------

local function start()
	if active then
		ns.say("camp probe already running")
		return
	end
	db()
	wipe(eventSamples)
	wipe(knownVignettes)
	local ok, err = pcall(probe.RegisterAllEvents, probe)
	if not ok then
		ns.say("RegisterAllEvents failed (%s), falling back to a fixed event list", tostring(err))
		for _, e in ipairs({ "UNIT_AURA", "PLAYER_CAMPING", "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE",
			"UI_ERROR_MESSAGE", "PLAYER_SOFT_INTERACT_CHANGED", "VIGNETTES_UPDATED",
			"VIGNETTE_MINIMAP_UPDATED", "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION" }) do
			pcall(probe.RegisterEvent, probe, e)
		end
		for e in pairs(CAST_EVENTS) do pcall(probe.RegisterUnitEvent, probe, e, "player") end
	end
	active = true
	record("probe_start", {
		cvarSoftInteract = ns.safeCall(C_CVar.GetCVar, "SoftTargetInteract"),
	})
	snapshotAuras()
	pollVignettes()
	ticker = C_Timer.NewTicker and C_Timer.NewTicker(VIGNETTE_POLL, pollVignettes)
	ns.say("camp probe started. Light or approach a fire, /sit for a minute, hover objects; /fad camp mark <note> to annotate.")
end

local function stop()
	if not active then return end
	record("probe_stop")
	active = false
	probe:UnregisterAllEvents()
	if ticker then ticker:Cancel() ticker = nil end
	ns.say("camp probe stopped: %d entries. /reload to write the file.", #db().log)
end

function ns.campCommand(arg)
	local sub, rest = strsplit(" ", arg or "", 2)
	sub = (sub or ""):lower()
	if sub == "start" then
		start()
	elseif sub == "stop" then
		stop()
	elseif sub == "mark" then
		record("mark", { note = rest or "" })
		ns.say("marked: %s", rest or "")
	elseif sub == "clear" then
		db().log = {}
		ns.say("camp log cleared")
	else
		ns.say("/fad camp start | stop | mark <note> | clear  (%d entries%s)",
			#db().log, active and ", running" or "")
	end
end
