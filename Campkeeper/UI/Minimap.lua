local ADDON_NAME, ns = ...
local L = ns.L

-- LibDataBroker launcher + LibDBIcon minimap button.
-- Left click: window (settings until the window exists); right click: settings.
local Minimap = {}
ns.MinimapButton = Minimap

local ICON = "Interface\\Icons\\Spell_Fire_Fire"

function Minimap:Init()
  local ldb = LibStub("LibDataBroker-1.1")
  self.object = ldb:NewDataObject(ADDON_NAME, {
    type = "launcher",
    text = ADDON_NAME,
    icon = ICON,
    OnClick = function(_, button)
      if button == "RightButton" or not ns.Window then
        ns.Options:Open()
      else
        ns.Window:Toggle()
      end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine(ADDON_NAME)
      ns.callbacks:Fire("MINIMAP_TOOLTIP", tooltip) -- alts' cooldowns etc. add lines here
      tooltip:AddLine(L["Left click: open window"], 0.2, 1, 0.2)
      tooltip:AddLine(L["Right click: settings"], 0.2, 1, 0.2)
    end,
  })
  self.icon = LibStub("LibDBIcon-1.0")
  self.icon:Register(ADDON_NAME, self.object, ns.db.profile.minimap)

  ns.RegisterCallback(self, "SETTINGS_CHANGED", function(_, key, value)
    if key == "minimap.hide" then
      if value then self.icon:Hide(ADDON_NAME) else self.icon:Show(ADDON_NAME) end
    end
  end)
end
