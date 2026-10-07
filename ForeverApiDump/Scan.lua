-- ID range scanner: collects names, tooltips and descriptions of items and
-- spells straight from the client, for building static catalogs.
-- Usage: /fad scan items 279000 281000 | /fad scan spells 1229700 1231000 | /fad scan camp

local _, ns = ...

local BATCH = 40          -- ids requested per step
local LOAD_TIMEOUT = 3    -- seconds to wait for server data per batch

-- Ranges around the camp IDs seen by the camp probe
local CAMP_RANGES = {
	{ "items", 279000, 281000 },
	{ "spells", 1229600, 1231200 },
	{ "spells", 1283300, 1283500 },
	{ "spells", 1307100, 1307500 },
}

local pending = {}
local loader = CreateFrame("Frame")
loader:RegisterEvent("ITEM_DATA_LOAD_RESULT")
loader:RegisterEvent("SPELL_DATA_LOAD_RESULT")
loader:SetScript("OnEvent", function(_, _, id)
	pending[id] = nil
end)

local function db()
	ForeverApiDumpDB.scan = ForeverApiDumpDB.scan or { items = {}, spells = {} }
	return ForeverApiDumpDB.scan
end

local function lines(tooltipData)
	if type(tooltipData) ~= "table" or type(tooltipData.lines) ~= "table" then return nil end
	local out = {}
	for i, line in ipairs(tooltipData.lines) do
		local left, right = line.leftText, line.rightText
		out[i] = (right and right ~= "") and (tostring(left) .. " | " .. tostring(right)) or tostring(left)
	end
	return out
end

local function exists(kind, id)
	if kind == "items" then
		return ns.safeCall(C_Item.GetItemInfoInstant, id) ~= nil
	end
	return ns.safeCall(C_Spell.DoesSpellExist, id) and true or false
end

local function requestLoad(kind, id)
	pending[id] = true
	if kind == "items" then
		ns.safeCall(C_Item.RequestLoadItemDataByID, id)
	else
		ns.safeCall(C_Spell.RequestLoadSpellData, id)
	end
end

local function read(kind, id)
	if kind == "items" then
		local name, _, quality, itemLevel, reqLevel, itemType, itemSubType, _, equipLoc, icon,
			sellPrice, classID, subclassID = ns.safeCall(C_Item.GetItemInfo, id)
		return ns.deepCopy({
			name = name, quality = quality, itemLevel = itemLevel, reqLevel = reqLevel,
			itemType = itemType, itemSubType = itemSubType, equipLoc = equipLoc, icon = icon,
			sellPrice = sellPrice, classID = classID, subclassID = subclassID,
			spellName = ns.safeCall(C_Item.GetItemSpell, id),
			tooltip = lines(ns.safeCall(C_TooltipInfo.GetItemByID, id)),
		})
	end
	local info = ns.safeCall(C_Spell.GetSpellInfo, id) or {}
	return ns.deepCopy({
		name = info.name, icon = info.iconID, castTime = info.castTime,
		minRange = info.minRange, maxRange = info.maxRange,
		description = ns.safeCall(C_Spell.GetSpellDescription, id),
		tooltip = lines(ns.safeCall(C_TooltipInfo.GetSpellByID, id)),
	})
end

local function waitForLoads()
	local deadline = GetTime() + LOAD_TIMEOUT
	while next(pending) and GetTime() < deadline do
		coroutine.yield()
	end
	wipe(pending)
end

local function scanRange(kind, from, to)
	local store = db()[kind]
	local found, batch = 0, {}
	local function flush()
		waitForLoads()
		for _, id in ipairs(batch) do
			store[id] = read(kind, id)
			found = found + 1
		end
		wipe(batch)
	end
	for id = from, to do
		if exists(kind, id) then
			batch[#batch + 1] = id
			requestLoad(kind, id)
			if #batch >= BATCH then flush() end
		end
		if id % 500 == 0 then coroutine.yield() end
	end
	flush()
	ns.say("scan %s %d-%d: %d found", kind, from, to, found)
end

local worker
local function step()
	if not worker then return end
	local ok, err = coroutine.resume(worker)
	if not ok then
		worker = nil
		ns.say("scan failed: %s", tostring(err))
	elseif coroutine.status(worker) == "dead" then
		worker = nil
		ns.say("scan done. /reload to write the file.")
	else
		C_Timer.After(0.05, step)
	end
end

local function run(ranges)
	if worker then
		ns.say("a scan is already running")
		return
	end
	worker = coroutine.create(function()
		for _, r in ipairs(ranges) do scanRange(r[1], r[2], r[3]) end
	end)
	step()
end

function ns.scanCommand(arg)
	local kind, from, to = strsplit(" ", (arg or ""):lower())
	from, to = tonumber(from), tonumber(to)
	if kind == "camp" then
		run(CAMP_RANGES)
	elseif (kind == "items" or kind == "spells") and from and to and to >= from then
		run({ { kind, from, to } })
	elseif kind == "clear" then
		ForeverApiDumpDB.scan = nil
		ns.say("scan data cleared")
	else
		ns.say("/fad scan camp | items <from> <to> | spells <from> <to> | clear")
	end
end
