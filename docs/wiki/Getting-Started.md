# Getting started with Campkeeper

## Install

- **CurseForge app** or **Wago app**: search for *Campkeeper* and install it for *World of Warcraft: Forever*.
- **By hand**: download the zip from [Releases](https://github.com/Vikquick/Campkeeper/releases) and unpack the `Campkeeper` folder into `Interface\AddOns` of your Forever game folder.

Optional: [TomTom](https://www.curseforge.com/wow/addons/tomtom) for nicer waypoints from map pins.

## Commands

| Command | What it does |
|---|---|
| `/ck` or `/campkeeper` | Open the Campkeeper window |
| `/ck config` | Settings |
| `/ck debug` | Diagnostic log; attach it to bug reports |
| `/ck report` | Beta data summary (only while *Forever* is in beta) |

`/camp` is taken by the game itself: it logs you out. That is why the addon uses `/ck`.

The **minimap button** opens the window on left click and the settings on right click.

## The camp panel

Walk up to a campfire and a small panel appears next to your buffs. It hides again when you leave, and always in combat.

- The title shows the fire, used and free places, and when **your own** fire goes out.
- **Placed** objects are listed with their effect.
- Objects **you** can add right now say *click to place*: one click places the item from your bags (out of combat only).
- *Covered by a class buff* means you already have the class buff this object's bonus does not stack with.
- At the bottom: the sitting countdown, then the time your Camp Benefits end, or the time your camping cooldown is ready.

## Alerts

Turn each one on or off in `/ck config`:

- a camp is nearby;
- Camp Benefits received;
- Camp Benefits end in 5 minutes;
- camping items are ready again;
- your campfire goes out in 1 minute.

## Camps on the map

- Your own camps and camps you used appear on the **world map** and the **minimap**.
- Hover a pin for its age, the time until it goes out, its source and its objects; click it for a waypoint.
- Camps are shared with your **guild** and your **group** automatically. In the settings you can also share them in a hidden **shared channel** with other Campkeeper users.
- A camp reported by only one stranger is shown faded until a second player confirms it.

## The window (`/ck`)

- **Catalog**: every camp object by profession and tier, the skill it needs, what it replaces, and which ones you know how to make.
- **Planner**: who in your group lights the fire and who places which object. It knows that each member places one camping item at a time, skips bonuses your group already has from class buffs, and can post the plan to group chat. Choose a goal: leveling, dungeon or crafting.
- **Alts**: professions, camping items, recipes and the camping cooldown of all your characters.

Group members without Campkeeper are listed too, but their professions are unknown, so the planner cannot give them a task.

## Something is wrong?

Open an [issue](https://github.com/Vikquick/Campkeeper/issues) and paste the output of `/ck debug`. See also [[FAQ]] and [[Beta notes|Beta-Notes]].
