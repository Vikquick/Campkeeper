local ADDON_NAME, ns = ...
local L = ns.L

-- Main window: tabs Catalog / Planner / Alts. Each tab module provides :Create(parent) and :Refresh().
local Window = { WIDTH = 700, HEIGHT = 470 }
ns.Window = Window

local frame, tabs, contents
local TABS = { { "CatalogTab", "Catalog" }, { "PlannerTab", "Planner" }, { "AltsTab", "Alts" } }

local function selectTab(i)
  Window.current = i
  if PanelTemplates_SetTab then PanelTemplates_SetTab(frame, i) end
  for j, c in ipairs(contents) do c:SetShown(j == i) end
  ns[TABS[i][1]]:Refresh()
end

local function create()
  frame = CreateFrame("Frame", "CampkeeperWindow", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(Window.WIDTH, Window.HEIGHT)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if frame.TitleText then frame.TitleText:SetText(ADDON_NAME) end
  table.insert(UISpecialFrames, "CampkeeperWindow") -- Esc closes it

  tabs, contents = {}, {}
  for i, def in ipairs(TABS) do
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 12, -30)
    content:SetPoint("BOTTOMRIGHT", -12, 12)
    content:Hide()
    contents[i] = content
    ns[def[1]]:Create(content)

    local tab = CreateFrame("Button", "CampkeeperWindowTab" .. i, frame, "PanelTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(L[def[2]])
    if i == 1 then tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, 2)
    else tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -14, 0) end
    tab:SetScript("OnClick", function() selectTab(i) end)
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
    tabs[i] = tab
  end
  frame.numTabs = #tabs
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #tabs) end
  frame:SetScript("OnShow", function() selectTab(Window.current or 1) end)
  frame:Hide()
  Window.frame, Window.tabs, Window.contents = frame, tabs, contents
end

function Window:Toggle()
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function Window:Show(tab)
  if not frame then create() end
  if tab then self.current = tab end
  if frame:IsShown() then selectTab(self.current or 1) else frame:Show() end
end

function Window:IsShown() return frame ~= nil and frame:IsShown() end

function Window:Select(i) selectTab(i) end

function Window:Init()
  local function refresh()
    if Window:IsShown() then ns[TABS[Window.current][1]]:Refresh() end
  end
  for _, event in ipairs({ "CATALOG_UPDATED", "PROFESSIONS_UPDATED", "CAMP_COOLDOWN_UPDATED" }) do
    ns.RegisterCallback(self, event, refresh)
  end
end
