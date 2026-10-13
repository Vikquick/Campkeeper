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
| `/ck announce` | Tell a chat about the camp you are standing at |
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
- **Announce** tells a chat about this camp: see below.

## Announcing a camp

Press **Announce** in the camp panel and pick a chat: your group or raid, your guild, or the general chat of the zone. Campkeeper posts one line with the campfire, the used places, the objects, the time until the fire goes out and a **map pin** anyone can click, with or without the addon:

> Basic Campfire, 2/3 - Fish Bowl, Camp Tent. 7 min left. [Map Pin Location] (Campkeeper T1 7m #19ngg)

- `/ck announce` does the same from the chat line. Without a word after it, it picks your group, then your guild, then general chat; `/ck announce group`, `guild` or `general` picks the chat.
- Nothing is posted unless you press the button or type the command.
- The same camp goes to the same chat at most once in 2 minutes.
- At someone else's camp Campkeeper knows only the place until you get the Camp Benefits there: sit by the fire first, and the announcement will list the objects. Before that the line is just *Camp here* with the map pin.
- **Language.** By default the line is written in the language of your game. In the settings (*Language of announcements*) you can make it English or Russian instead, for example when you play a Russian client on a realm where general chat is English.
- The short code at the end tells other Campkeeper users the fire, the time left and every object of the camp. Their addon reads it whatever language the line is in and shows the objects in their own language.

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
- **Camps from chat.** When anyone posts a map pin together with a word about a camp ("camp", "campfire", and the same in Russian, German, French and Spanish), Campkeeper puts that camp on your map, faded, for 10 minutes. The player does not need the addon. A Campkeeper announcement also brings the fire tier, the time left and the objects of the camp, in any language. You can turn this off in the settings (*Read camps from chat*).

## The window (`/ck`)

- **Catalog**: every camp object by profession and tier, the skill it needs, what it replaces, and which ones you know how to make.
- **Planner**: who in your group lights the fire and who places which object. It knows that each member places one camping item at a time, skips bonuses your group already has from class buffs, and can post the plan to group chat. Choose a goal: leveling, dungeon or crafting.
- **Alts**: professions, camping items, recipes and the camping cooldown of all your characters.

Group members without Campkeeper are listed too, but their professions are unknown, so the planner cannot give them a task.

### Camp benefits of the group

Next to every member the Planner shows whether they have **Camp Benefits** and for how long, with or without Campkeeper on their side: *benefits: 40 min*, *no camp benefits*, or *benefits unknown* when the member is too far away. **Post camp benefits to group chat** tells the group who still has to sit by the fire.

At a **ready check** you get the same summary in your own chat window; nothing is sent to the group. The game hides other players' buffs in combat, so the list updates between fights. The ready-check summary can be turned off in the settings.

## Something is wrong?

Open an [issue](https://github.com/Vikquick/Campkeeper/issues) and paste the output of `/ck debug`. See also [[FAQ]] and [[Beta notes|Beta-Notes]].
