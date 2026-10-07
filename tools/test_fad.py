"""End-to-end check: run the addon in Lua 5.1 with a mocked WoW API,
write SavedVariables the way the client does, then parse and report.

  python tools/test_fad.py
"""

import sys
import tempfile
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import fad  # noqa: E402

MOCK = r"""
local timers, frames = {}, {}
function GetBuildInfo() return BUILD_VERSION, "70245", "Oct 1 2026", INTERFACE end
function GetLocale() return "ruRU" end
date = os.date
function debugprofilestop() return os.clock() * 1000 end
function InCombatLockdown() return false end
function issecretvalue(v) return v == SECRET end
SECRET = {}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
  local a, b = s:match("^(%S*)%s*(.*)$")
  if b == "" then b = nil end
  return a, b
end
SlashCmdList = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
function PumpTimers()
  local n = 0
  while #timers > 0 do table.remove(timers, 1)(); n = n + 1 end
  return n
end
function CreateFrame()
  local f = { scripts = {}, events = {} }
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:RegisterAllEvents() self.all = true end
  function f:UnregisterAllEvents() self.all = nil; self.events = {} end
  table.insert(frames, f)
  return f
end
function FireAll(event, ...)
  for _, f in ipairs(frames) do
    if f.scripts.OnEvent and (f.all or f.events[event]) then f.scripts.OnEvent(f, event, ...) end
  end
end
WOW_PROJECT_ID = PROJECT
WOW_PROJECT_MAINLINE = 1
C_UnitAuras = { GetAuraDataByIndex = function() end, Version = 2 }
C_Extra = EXTRA_NS and { Secret = function() end } or nil
Enum = { PowerType = { Mana = 0, Rage = 1 } }
Constants = { MaxLevel = { Value = 60 } }
C_Console = { GetAllCommands = function()
  return { { command = "nameplateMaxDistance", help = "dist", commandType = 0 } }
end }
C_AddOns = { LoadAddOn = function(name)
  if name ~= "Blizzard_APIDocumentationGenerated" then return end
  local sys = { Name = "UnitAuras", Type = "System", Namespace = "C_UnitAuras",
    Functions = {
      { Name = "GetAuraDataByIndex", Type = "Function", SecretReturns = SECRET_FLAG,
        Arguments = { { Name = "unit", Type = "UnitToken", Nilable = false },
                      { Name = "index", Type = "luaIndex", Nilable = false },
                      { Name = "filter", Type = "cstring", Nilable = true } },
        Returns = { { Name = "aura", Type = "AuraData", Nilable = true } } },
    },
    Events = { { Name = "UnitAura", Type = "Event", LiteralName = "UNIT_AURA",
      Payload = { { Name = "unitTarget", Type = "UnitToken", Nilable = false } } } },
    Tables = {},
  }
  sys.Functions[1].System = sys -- back reference, like the real mixins
  APIDocumentation = { systems = { sys }, AddDocumentationTable = function() end }
end }

-- WoW-style SavedVariables writer
local function key(k)
  if type(k) == "string" then return string.format("[%q]", k) end
  return "[" .. tostring(k) .. "]"
end
local function write(v, indent, out)
  local t = type(v)
  if t == "string" then table.insert(out, string.format("%q", v))
  elseif t == "number" or t == "boolean" then table.insert(out, tostring(v))
  elseif t == "table" then
    table.insert(out, "{\n")
    local n = #v
    for i = 1, n do
      table.insert(out, indent .. "\t"); write(v[i], indent .. "\t", out)
      table.insert(out, ", -- [" .. i .. "]\n")
    end
    for k, val in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
        table.insert(out, indent .. "\t" .. key(k) .. " = "); write(val, indent .. "\t", out)
        table.insert(out, ",\n")
      end
    end
    table.insert(out, indent .. "}")
  end
end
function Serialize(name, v)
  local out = { "\n", name, " = " }
  write(v, "", out)
  table.insert(out, "\n")
  return table.concat(out)
end
"""


CAMP_MOCK = r"""
local now = 100
function GetTime() return now end
function Advance(s) now = now + s end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer.NewTicker = function() return { Cancel = function() end } end
C_CVar = { GetCVar = function() return "1" end }
C_Map = {
  GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.41, 0.65 end } end,
}
function UnitPosition() return -9000.5, 120.25, 56, 0 end
function UnitName() return "Basic Campfire" end
function UnitGUID() return "GameObject-0-1-2-3-4-500001-0000" end
AURAS = {
  [7] = { auraInstanceID = 7, spellId = 1300001, name = "Camp Benefits", isHelpful = true,
          duration = 3600, expirationTime = 3700, points = { 5, 10 } },
}
C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
  if filter == "HELPFUL" and i == 1 then return AURAS[7] end
end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(unit, id) return AURAS[id] end
C_TooltipInfo = {
  GetUnitBuffByAuraInstanceID = function(unit, id)
    return { lines = { { leftText = "Camp Benefits" }, { leftText = "Stamina +5", rightText = SECRET } } }
  end,
}
C_Spell = { GetSpellInfo = function(id) return { name = "Build Campfire" } end }
C_VignetteInfo = {
  GetVignettes = function() return VIGNETTES or {} end,
  GetVignetteInfo = function(guid) return { name = "Campfire", vignetteID = 42, atlasName = "camp" } end,
  GetVignettePosition = function() return { GetXY = function() return 0.4, 0.6 end } end,
}
TooltipDataProcessor = { AllTypes = "ALL" }
function TooltipDataProcessor.AddTooltipPostCall(_, fn) TOOLTIP_HOOK = fn end

-- Scanner: items 279950 and 279960 exist, spell 1307227 exists
local ITEMS = { [279950] = "Reagent Bot", [279960] = "Lodestone" }
C_Item = {
  GetItemInfoInstant = function(id) if ITEMS[id] then return id end end,
  RequestLoadItemDataByID = function(id) FireAll("ITEM_DATA_LOAD_RESULT", id, true) end,
  GetItemInfo = function(id)
    return ITEMS[id], "link", 1, 20, 0, "Misc", "Camp", 1, "", 134400, 25, 15, 0
  end,
  GetItemSpell = function(id) return "Place", 1307266 end,
}
C_TooltipInfo.GetItemByID = function(id) return { lines = { { leftText = ITEMS[id] } } } end
C_TooltipInfo.GetSpellByID = function(id) return { lines = { { leftText = "Basic Campfire" } } } end
C_Spell.DoesSpellExist = function(id) return id == 1307227 end
C_Spell.RequestLoadSpellData = function(id) FireAll("SPELL_DATA_LOAD_RESULT", id, true) end
C_Spell.GetSpellDescription = function() return "Places a campfire." end
"""


def load_addon(lua):
    ns = lua.table()
    toc = (ROOT / "ForeverApiDump" / "ForeverApiDump.toc").read_text(encoding="utf-8")
    for line in toc.splitlines():
        if line.strip().endswith(".lua"):
            source = (ROOT / "ForeverApiDump" / line.strip()).read_text(encoding="utf-8")
            lua.eval("loadstring")(source)("ForeverApiDump", ns)


def run_client(version, interface, project, extra_ns, secret_flag):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.BUILD_VERSION, g.INTERFACE, g.PROJECT = version, interface, project
    g.EXTRA_NS, g.SECRET_FLAG = extra_ns, secret_flag
    lua.execute(MOCK)
    lua.execute(CAMP_MOCK)
    load_addon(lua)
    g.FireAll("ADDON_LOADED", "ForeverApiDump")
    g.SlashCmdList.FOREVERAPIDUMP("events start")
    g.FireAll("UNIT_AURA", "player", g.SECRET)
    g.SlashCmdList.FOREVERAPIDUMP("dump")
    g.PumpTimers()

    # Camp probe scenario
    g.SlashCmdList.FOREVERAPIDUMP("camp start")
    g.FireAll("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1300100)
    g.FireAll("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-2", 999)
    lua.execute("VIGNETTES = { 'Vignette-1' }")
    g.FireAll("VIGNETTES_UPDATED")
    g.FireAll("UNIT_AURA", "player", lua.eval("{ addedAuras = { AURAS[7] } }"))
    g.FireAll("UNIT_AURA", "player", lua.eval("{ updatedAuraInstanceIDs = { 7 }, removedAuraInstanceIDs = { 3 } }"))
    g.FireAll("PLAYER_CAMPING")
    g.FireAll("PLAYER_SOFT_INTERACT_CHANGED", lua.eval("nil"), "GameObject-0-1-2-3-4-500001-0000")
    for _ in range(8):
        g.FireAll("BAG_UPDATE", 0)
    g.FireAll("COMBAT_LOG_EVENT_UNFILTERED")
    g.TOOLTIP_HOOK(lua.eval("{ GetName = function() return 'GameTooltip' end }"),
                   lua.eval("{ type = 3, id = 500001, lines = { { leftText = 'Basic Campfire' } } }"))
    g.SlashCmdList.FOREVERAPIDUMP("camp mark sat down")
    lua.execute("VIGNETTES = {}")
    g.FireAll("VIGNETTES_UPDATED")
    g.SlashCmdList.FOREVERAPIDUMP("camp stop")

    g.SlashCmdList.FOREVERAPIDUMP("scan camp")
    g.PumpTimers()
    return g.Serialize("ForeverApiDumpDB", g.ForeverApiDumpDB)


def check_scan(dump_path):
    scan = fad.load_saved_variables(dump_path)["ForeverApiDumpDB"]["scan"]
    items, spells = scan["items"], scan["spells"]
    assert set(items) == {279950, 279960}, items.keys()
    assert items[279950]["name"] == "Reagent Bot" and items[279950]["classID"] == 15, items[279950]
    assert items[279950]["spellName"] == "Place" and items[279950]["tooltip"] == ["Reagent Bot"]
    assert set(spells) == {1307227} and spells[1307227]["description"] == "Places a campfire.", spells


def check_camp_log(dump_path):
    db = fad.load_saved_variables(dump_path)["ForeverApiDumpDB"]
    log = db["camp"]["log"]
    kinds = [e["kind"] for e in log]
    for k in ("probe_start", "aura_snapshot", "cast", "vignette_added", "aura_added", "aura_updated",
              "aura_removed", "event", "soft_interact", "tooltip", "mark", "vignette_removed", "probe_stop"):
        assert k in kinds, (k, kinds)
    casts = [e for e in log if e["kind"] == "cast"]
    assert len(casts) == 1 and casts[0]["spellID"] == 1300100 and casts[0]["name"] == "Build Campfire", casts
    added = next(e for e in log if e["kind"] == "aura_added")
    assert added["tooltip"] == ["Camp Benefits", "Stamina +5 | <secret>"], added
    assert added["pos"]["mapID"] == 1429 and added["pos"]["x"] == 0.41, added["pos"]
    events = [e["event"] for e in log if e["kind"] == "event"]
    assert events.count("BAG_UPDATE") == 5, events
    assert "PLAYER_CAMPING" in events and "COMBAT_LOG_EVENT_UNFILTERED" not in events
    assert next(e for e in log if e["kind"] == "mark")["note"] == "sat down"


def main():
    out = Path(tempfile.mkdtemp())
    forever = out / "forever.lua"
    retail = out / "retail.lua"
    forever.write_text(run_client("1.60.1", 16001, 99, True, "AllowedWhenUntainted"), encoding="utf-8")
    retail.write_text(run_client("12.1.0", 120100, 1, False, None), encoding="utf-8")

    check_camp_log(forever)
    check_scan(forever)
    dump = fad.load_dump(forever)
    assert dump["meta"]["interface"] == 16001, dump["meta"]
    assert dump["meta"]["projects"]["WOW_PROJECT_ID"] == 99
    assert dump["globals"]["C_UnitAuras"] == "table"
    assert dump["namespaces"]["C_UnitAuras"]["GetAuraDataByIndex"] == "function"
    fn = dump["apidocs"][0]["Functions"][0]
    assert fn["System"] == "<cycle>", fn
    assert dump["events_seen"]["UNIT_AURA"]["args"] == ["string", "secret"]
    idx = fad.api_index(dump)
    assert idx["C_UnitAuras.GetAuraDataByIndex"]["flags"] == {"SecretReturns": "AllowedWhenUntainted"}
    assert "UNIT_AURA" in idx

    fad.main(["report", str(forever), "-o", str(out / "reference.md")])
    fad.main(["diff", str(forever), str(retail), "-o", str(out / "diff.md")])
    diff = (out / "diff.md").read_text(encoding="utf-8")
    assert "`C_Extra`" in diff and "SecretReturns=AllowedWhenUntainted" in diff, diff
    print((out / "reference.md").read_text(encoding="utf-8"))
    print(diff)
    print("OK")


if __name__ == "__main__":
    main()
