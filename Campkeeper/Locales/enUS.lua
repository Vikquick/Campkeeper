local L = LibStub("AceLocale-3.0"):NewLocale("Campkeeper", "enUS", true)

-- Interface strings only; game object names always come from the client.

L["Loading..."] = true

-- Slash commands
L["Commands:"] = true
L["/ck - open the Campkeeper window"] = true
L["/ck config - open settings"] = true
L["/ck debug [all||clear] - show the debug log"] = true
L["Debug log: %d records"] = true
L["Debug log cleared."] = true

-- Options
L["General"] = true
L["Show camp panel"] = true
L["Show the camp panel next to your buffs while you are near a camp."] = true
L["Show minimap button"] = true

-- Minimap button
L["Left click: open window"] = true
L["Right click: settings"] = true

-- Alerts
L["Alerts"] = true
L["Camp nearby"] = true
L["Benefits received"] = true
L["Benefits ending soon"] = true
L["Camping cooldown ready"] = true
L["Own campfire going out"] = true
L["A camp is nearby: sit by the fire for its benefits."] = true
L["Camp benefits received."] = true
L["Camp benefits end in 5 minutes."] = true
L["Camping items are ready again."] = true
L["Your campfire goes out in 1 minute."] = true

-- Camp panel
L["Camp"] = true
L["Campfire goes out in %s"] = true
L["Camping cooldown: %s"] = true
L["placed"] = true
L["click to place"] = true
L["covered by a class buff"] = true
L["Sit by the fire to get the camp benefits"] = true
L["Stay seated: %d s"] = true
L["Benefits until %s"] = true
L["Camping items are on cooldown: %s"] = true
L["Too close to another object or creature."] = true

-- Map pins
L["Age: %s"] = true
L["Goes out in: %s"] = true
L["Source: %s"] = true
L["your camp"] = true
L["seen by you"] = true
L["group"] = true
L["guild"] = true
L["shared channel"] = true
L["Unconfirmed: reported by one player"] = true
L["Click: set a waypoint"] = true

-- Sharing
L["Sharing"] = true
L["Share camps in the shared channel"] = true
L["Guild and group sharing always stay on."] = true
L["Someone uses an incompatible Campkeeper version. Please update the addon."] = true

-- Planner
L["Camp plan:"] = true

-- Window
L["Catalog"] = true
L["Planner"] = true
L["Alts"] = true
L["Tier %d"] = true
L["Requires: %s (%d)"] = true
L["Replaces: %s"] = true
L["You know how to make it"] = true
L["skill %d"] = true
L["known"] = true
L["Alchemy"] = true
L["Blacksmithing"] = true
L["Enchanting"] = true
L["Engineering"] = true
L["First Aid"] = true
L["Fishing"] = true
L["Herbalism"] = true
L["Leatherworking"] = true
L["Mining"] = true
L["Skinning"] = true
L["Tailoring"] = true
L["Cooking"] = true
L["unknown"] = true
L["ready"] = true
L["no professions"] = true
L["Camping cooldown"] = true
L["%s / camp items: %d"] = true
L["Recipes: %s / blueprints: %s"] = true
L["Leveling"] = true
L["Dungeon"] = true
L["Crafting"] = true
L["%d slots"] = true
L["Plan"] = true
L["you"] = true
L["via Campkeeper"] = true
L["Nobody can light this fire (Cooking %d)"] = true

-- Planner tab
L["Who places what in the group camp"] = true
L["Each member can place one camping item per hour (shared cooldown)."] = true
L["Goal:"] = true
L["Campfire:"] = true
L["%s, %d places"] = true
L["Members"] = true
L["no Campkeeper"] = true
L["no professions known"] = true
L["Without Campkeeper: %s - their professions are unknown and not planned."] = true
L["Post the plan to group chat"] = true
L["You are alone: other objects need more group members."] = true
L["Every member already places something; more members would fill the free places."] = true
L["The remaining members have no profession skill for the other objects."] = true
L["Skipped, a class in the group gives this buff: %s"] = true

-- Beta research
L["/ck report [clear] - beta data summary"] = true
L["Beta data cleared."] = true
L["Beta data (stays on your computer):"] = true
L["Collect beta data for the developer"] = true
L["Stays on your computer in the saved variables; /ck report shows it."] = true
L["Q1 benefits tooltips: %d; higher tiers seen: %s; unknown names: %s"] = true
L["Q2 aura radius: appears at %s yd, disappears at %s yd (%d samples)"] = true
L["Q3 auras gained at camps: %d; with a tent: %s"] = true
L["Q4 camp blueprints seen: %d (learned: %d)"] = true
L["Q5 sent: %s; own echo: %s; from others: %s"] = true
L["Blocked actions: %d"] = true
L["Campfire burned: %s s"] = true
L["Durations: sitting %s s; benefits %s s"] = true
L["Placement errors: %s"] = true
L["Catalog check (build %s): missing items %d, missing spells %d"] = true
L["Catalog check: not run yet"] = true
L["Q5 queued: %s (why: %s); sent from the queue: %s"] = true
