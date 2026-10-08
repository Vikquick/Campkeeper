local ADDON_NAME, ns = ...

local Campkeeper = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
ns.addon = Campkeeper
ns.L = LibStub("AceLocale-3.0"):GetLocale(ADDON_NAME)
local L = ns.L

-- Core modules publish state changes here; UI subscribes with ns.RegisterCallback(owner, event, handler).
ns.callbacks = LibStub("CallbackHandler-1.0"):New(ns)

ns.DB_VERSION = 1
ns.defaults = {
  global = {
    debugLog = {},
    chars = {},
  },
  char = {},
  profile = {
    panel = { enabled = true },
    minimap = { hide = false },
    alerts = { near = true, gained = true, ending = true, cooldown = true, fire = true },
  },
}

local DEBUG_TAIL = 20

function Campkeeper:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("CampkeeperDB", ns.defaults, true)
  ns.db = self.db
  -- Not a default: AceDB strips defaults on logout, and migrations need the stored value.
  self.db.global.dbVersion = self.db.global.dbVersion or ns.DB_VERSION
  ns.Log:Attach(self.db.global.debugLog)
  ns.Alerts:AddOptions()
  ns.Options:Register()
  ns.MinimapButton:Init()
  -- Not /camp: that is the client's built-in logout command and always wins.
  self:RegisterChatCommand("ck", "ChatCommand")
  self:RegisterChatCommand("campkeeper", "ChatCommand")
  ns.callbacks:Fire("INITIALIZED")
end

local function onUnitEvent(_, event, _, ...)
  if event == "UNIT_AURA" then
    ns.CampState:OnUnitAura((...))
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, spellID = ...
    ns.OwnCamp:OnSpellSucceeded(spellID)
  elseif event == "UNIT_SPELLCAST_SENT" then
    local _, _, spellID = ...
    local placed = ns.Catalog:ByPlaceSpell(spellID)
    if placed then ns.OwnCamp:NoteAttempt(placed.key) end
  end
end

-- Client events -> Core modules. Core never touches frames; this is the only wiring point.
function Campkeeper:OnEnable()
  self:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, itemID, success) ns.Catalog:OnItemLoaded(itemID, success) end)
  self:RegisterEvent("SPELL_DATA_LOAD_RESULT", function(_, spellID, success) ns.Catalog:OnSpellLoaded(spellID, success) end)

  local unitFrame = CreateFrame("Frame")
  unitFrame:RegisterUnitEvent("UNIT_AURA", "player")
  unitFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  unitFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
  unitFrame:SetScript("OnEvent", onUnitEvent)
  self.unitFrame = unitFrame

  self:RegisterEvent("PLAYER_REGEN_ENABLED", function() ns.CampState:OnCombatEnded() end)
  self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    ns.CampState:Rebuild()
    ns.Professions:ScanAll()
    ns.OwnCamp:UpdateCooldown()
  end)
  self:RegisterEvent("UI_ERROR_MESSAGE", function(_, errorType) ns.OwnCamp:OnUIError(errorType) end)
  self:RegisterEvent("BAG_UPDATE_DELAYED", function()
    ns.Professions:ScanBags()
    ns.OwnCamp:UpdateCooldown()
  end)
  self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() ns.OwnCamp:UpdateCooldown() end)
  self:RegisterEvent("SKILL_LINES_CHANGED", function() ns.Professions:ScanProfessions() end)
  self:RegisterEvent("TRADE_SKILL_SHOW", function() ns.Professions:ScanRecipes(true) end)
  self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function() ns.Professions:ScanRecipes(true) end)
  self:RegisterEvent("NEW_RECIPE_LEARNED", function() ns.Professions:ScanRecipes(false) end)

  ns.RegisterCallback(self, "CAMP_BENEFITS_GAINED", function(_, instanceID)
    ns.BenefitsParser:Parse(instanceID, function(composition) ns.CampState:SetBenefits(instanceID, composition) end)
  end)
  ns.RegisterCallback(self, "CAMP_BENEFITS_PARSED", function(_, composition, info)
    ns.OwnCamp:OnBenefitsParsed(composition, info)
  end)

  ns.CampState:Rebuild()
  ns.Professions:ScanAll()
  ns.OwnCamp:UpdateCooldown()
  ns.Alerts:Init()
  ns.Panel:Init()
  ns.callbacks:Fire("ENABLED")
end

function Campkeeper:PrintHelp()
  self:Print(L["Commands:"])
  self:Print(L["/ck - open the Campkeeper window"])
  self:Print(L["/ck config - open settings"])
  self:Print(L["/ck debug [all||clear] - show the debug log"])
end

function Campkeeper:PrintDebugLog(all)
  local entries = ns.Log:Entries()
  self:Print(L["Debug log: %d records"]:format(#entries))
  local from = all and 1 or math.max(1, #entries - DEBUG_TAIL + 1)
  for i = from, #entries do
    local e = entries[i]
    self:Print(("%s [%s] %s"):format(date("%H:%M:%S", e.t), e.cat, e.msg))
  end
end

function Campkeeper:ChatCommand(input)
  local cmd, arg = self:GetArgs(input, 2)
  cmd = cmd and cmd:lower()
  if cmd == "debug" then
    if arg == "clear" then
      ns.Log:Clear()
      self:Print(L["Debug log cleared."])
    else
      self:PrintDebugLog(arg == "all")
    end
  elseif cmd == "config" then
    ns.Options:Open()
  elseif cmd == nil and ns.Window then
    ns.Window:Toggle()
  else
    self:PrintHelp()
  end
end
