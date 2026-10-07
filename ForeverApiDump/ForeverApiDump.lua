-- Forever API Dump: snapshots the client's Lua API surface into SavedVariables.
-- Usage: /fad dump, then /reload so the client writes ForeverApiDumpDB to disk.

local ADDON_NAME, ns = ...

local MAX_DEPTH = 12
local YIELD_EVERY = 4000

local PREFIX = "|cff33ff99FAD|r: "
local function say(fmt, ...)
	print(PREFIX .. string.format(fmt, ...))
end

local isSecret = issecretvalue or function() return false end

---------------------------------------------------------------------------
-- Cooperative worker so a large dump does not freeze the client
---------------------------------------------------------------------------

local ops = 0
local function tick()
	ops = ops + 1
	if ops % YIELD_EVERY == 0 and coroutine.running() then
		coroutine.yield()
	end
end

local worker
local function step()
	if not worker then return end
	local ok, err = coroutine.resume(worker)
	if not ok then
		worker = nil
		say("dump failed: %s", tostring(err))
	elseif coroutine.status(worker) == "dead" then
		worker = nil
	else
		C_Timer.After(0, step)
	end
end

local function runWorker(fn)
	if worker then
		say("a dump is already running")
		return
	end
	worker = coroutine.create(fn)
	step()
end

---------------------------------------------------------------------------
-- Copy helpers: keep only serializable data, cut cycles and functions
---------------------------------------------------------------------------

local function copyPlain(value, depth, path)
	tick()
	if isSecret(value) then return "<secret>" end
	local t = type(value)
	if t == "string" or t == "number" or t == "boolean" then return value end
	if t ~= "table" then return nil end
	if path[value] then return "<cycle>" end
	if depth > MAX_DEPTH then return "<depth>" end

	path[value] = true
	local out = {}
	for k, v in pairs(value) do
		local kt = type(k)
		if (kt == "string" or kt == "number") and not isSecret(k) then
			local c = copyPlain(v, depth + 1, path)
			if c ~= nil then out[k] = c end
		end
	end
	path[value] = nil
	return out
end

local function deepCopy(value)
	return copyPlain(value, 0, {})
end

local function passIfOk(ok, ...)
	if ok then return ... end
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	return passIfOk(pcall(fn, ...))
end

ns.say, ns.isSecret, ns.deepCopy, ns.safeCall = say, isSecret, deepCopy, safeCall

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

local function collectMeta()
	local version, build, buildDate, interface = safeCall(GetBuildInfo)
	local meta = {
		version = version,
		build = build,
		buildDate = buildDate,
		interface = interface,
		locale = safeCall(GetLocale),
		dumpedAt = safeCall(date, "%Y-%m-%d %H:%M:%S"),
		projects = {},
	}
	for name, value in pairs(_G) do
		if type(name) == "string" and name:match("^WOW_PROJECT_") and type(value) == "number" then
			meta.projects[name] = value
		end
	end
	return meta
end

-- Every global name with its Lua type; C_* tables also get their member list.
local function collectGlobals()
	local globals, namespaces = {}, {}
	for name, value in pairs(_G) do
		tick()
		if type(name) == "string" and not isSecret(value) then
			local t = type(value)
			globals[name] = t
			if t == "table" and name:match("^C_") then
				local members = {}
				for member, mv in pairs(value) do
					if type(member) == "string" then
						members[member] = type(mv)
					end
				end
				namespaces[name] = members
			end
		end
	end
	return globals, namespaces
end

local function loadAddOnQuiet(name)
	local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
	return safeCall(load, name)
end

local function collectApiDocs()
	loadAddOnQuiet("Blizzard_APIDocumentation")
	loadAddOnQuiet("Blizzard_APIDocumentationGenerated")
	local docs = APIDocumentation
	if type(docs) ~= "table" then
		return nil, "APIDocumentation global not found"
	end
	if type(docs.systems) == "table" then
		return deepCopy(docs.systems)
	end
	return deepCopy(docs), "APIDocumentation.systems missing, dumped whole table"
end

local function collectCVars()
	if not (C_Console and C_Console.GetAllCommands) then return nil end
	return deepCopy(safeCall(C_Console.GetAllCommands))
end

---------------------------------------------------------------------------
-- Event recorder: which events actually fire, with payload arity and types
---------------------------------------------------------------------------

local recorder = CreateFrame("Frame")
local recording = false

recorder:SetScript("OnEvent", function(_, event, ...)
	local seen = ForeverApiDumpDB.events
	local entry = seen[event]
	if not entry then
		local types = {}
		for i = 1, select("#", ...) do
			local v = select(i, ...)
			types[i] = isSecret(v) and "secret" or type(v)
		end
		entry = { count = 0, args = types }
		seen[event] = entry
	end
	entry.count = entry.count + 1
end)

local function setRecording(on)
	if on == recording then return end
	if on then
		ForeverApiDumpDB.events = ForeverApiDumpDB.events or {}
		local ok, err = pcall(recorder.RegisterAllEvents, recorder)
		if not ok then
			say("RegisterAllEvents is not allowed: %s", tostring(err))
			return
		end
	else
		recorder:UnregisterAllEvents()
	end
	recording = on
	say("event recording %s", on and "started" or "stopped")
end

---------------------------------------------------------------------------
-- Dump
---------------------------------------------------------------------------

local function dump()
	local started = debugprofilestop()
	local result = { notes = {} }

	result.meta = collectMeta()
	say("build %s (%s), interface %s", tostring(result.meta.version),
		tostring(result.meta.build), tostring(result.meta.interface))

	result.globals, result.namespaces = collectGlobals()
	say("globals collected")

	local note
	result.apidocs, note = collectApiDocs()
	if note then table.insert(result.notes, note) end
	say("API documentation collected")

	result.enums = deepCopy(Enum)
	result.constants = deepCopy(Constants)
	result.cvars = collectCVars()

	ForeverApiDumpDB.dump = result
	say("done in %.1fs. Type /reload to write the file.", (debugprofilestop() - started) / 1000)
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
	if name ~= ADDON_NAME then return end
	ForeverApiDumpDB = ForeverApiDumpDB or {}
	self:UnregisterEvent("ADDON_LOADED")
end)

SLASH_FOREVERAPIDUMP1 = "/fad"
SlashCmdList.FOREVERAPIDUMP = function(msg)
	local cmd, rawArg = strsplit(" ", strtrim(msg or ""), 2)
	cmd = (cmd or ""):lower()
	local arg = rawArg and rawArg:lower()
	if cmd == "camp" and ns.campCommand then
		ns.campCommand(rawArg)
	elseif cmd == "scan" and ns.scanCommand then
		ns.scanCommand(rawArg)
	elseif cmd == "dump" then
		if InCombatLockdown() then
			say("leave combat first")
			return
		end
		runWorker(dump)
	elseif cmd == "events" then
		if arg == "start" then
			setRecording(true)
		elseif arg == "stop" then
			setRecording(false)
		elseif arg == "clear" then
			ForeverApiDumpDB.events = {}
			say("event log cleared")
		else
			say("/fad events start | stop | clear")
		end
	elseif cmd == "status" then
		local d = ForeverApiDumpDB.dump
		local n = 0
		for _ in pairs(ForeverApiDumpDB.events or {}) do n = n + 1 end
		say("last dump: %s; events recorded: %d%s",
			d and d.meta and tostring(d.meta.dumpedAt) or "none", n,
			recording and " (recording)" or "")
	else
		say("/fad dump | events start|stop|clear | camp start|stop|mark <note>|clear | status")
	end
end
