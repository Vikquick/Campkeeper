local ADDON_NAME, ns = ...
local L = ns.L

-- AceConfig options. Feature modules add their groups with Options:AddGroup before
-- Options:Register runs (OnInitialize), so the table is complete when it is registered.
local Options = {}
ns.Options = Options

local order = 10

local function profile() return ns.db.profile end

Options.table = {
  type = "group",
  name = ADDON_NAME,
  args = {
    general = {
      type = "group",
      name = L["General"],
      order = 1,
      inline = true,
      args = {
        panel = {
          type = "toggle",
          name = L["Show camp panel"],
          desc = L["Show the camp panel next to your buffs while you are near a camp."],
          width = "full",
          order = 1,
          get = function() return profile().panel.enabled end,
          set = function(_, v)
            profile().panel.enabled = v
            ns.callbacks:Fire("SETTINGS_CHANGED", "panel.enabled", v)
          end,
        },
        minimap = {
          type = "toggle",
          name = L["Show minimap button"],
          width = "full",
          order = 2,
          get = function() return not profile().minimap.hide end,
          set = function(_, v)
            profile().minimap.hide = not v
            ns.callbacks:Fire("SETTINGS_CHANGED", "minimap.hide", not v)
          end,
        },
      },
    },
  },
}

function Options:AddGroup(key, group)
  order = order + 1
  group.order = group.order or order
  self.table.args[key] = group
end

function Options:Register()
  local registry = LibStub("AceConfigRegistry-3.0")
  local dialog = LibStub("AceConfigDialog-3.0")
  registry:RegisterOptionsTable(ADDON_NAME, self.table)
  dialog:AddToBlizOptions(ADDON_NAME, ADDON_NAME)

  local profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(ns.db)
  registry:RegisterOptionsTable(ADDON_NAME .. "_Profiles", profiles)
  dialog:AddToBlizOptions(ADDON_NAME .. "_Profiles", profiles.name, ADDON_NAME)
end

-- Standalone AceConfig window: opening the Settings panel from addon code goes through
-- C_SettingsUtil.OpenSettingsPanel, which Forever marks as restricted.
function Options:Open()
  LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME)
end
