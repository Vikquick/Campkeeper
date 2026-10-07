local ADDON_NAME, ns = ...

local Campkeeper = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
ns.addon = Campkeeper

-- Core modules publish state changes here; UI subscribes with ns.RegisterCallback(owner, event, handler).
ns.callbacks = LibStub("CallbackHandler-1.0"):New(ns)

ns.DB_VERSION = 1
ns.defaults = {
  global = {},
  char = {},
  profile = {},
}

function Campkeeper:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("CampkeeperDB", ns.defaults, true)
  ns.db = self.db
  -- Not a default: AceDB strips defaults on logout, and migrations need the stored value.
  self.db.global.dbVersion = self.db.global.dbVersion or ns.DB_VERSION
  ns.callbacks:Fire("INITIALIZED")
end

function Campkeeper:OnEnable()
  ns.callbacks:Fire("ENABLED")
end
