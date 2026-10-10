# FAQ

**Why `/ck` and not `/camp`?**
`/camp` is a built-in game command: it logs you out. Campkeeper uses `/ck` and `/campkeeper`.

**Does it work in my language?**
Object names, buffs and items are read from your game client, so they appear in your language. The addon's own text is in English and Russian.

**Why does the panel disappear in combat?**
The game restricts what addons may do in combat. Campkeeper hides the panel there and brings it back when the fight ends, so it never blocks your actions.

**Why can I not place an object from the panel?**
Placing works out of combat only, needs a free place at the fire and a ready camping cooldown. If you stand too close to another object or a creature the game refuses as well; the panel tells you which of these it is.

**Why is a camp on my map faded?**
It was reported by one player who is not in your guild or group. It turns normal once a second player confirms it.

**What does Campkeeper send to other players?**
Camps: where they are, which fire, which objects and when the fire goes out. Your guild and group get them always; the shared channel only if you turn it on. Your group also gets your profession skills, so the planner can give you a task.

**What is `/ck report`?**
While *Forever* is in beta, Campkeeper can collect a few facts about camps (tooltip texts, aura timings, placement errors) to make the addon more accurate. They stay in your saved variables on your computer; nothing is sent anywhere. You can turn this off in the settings.

**The planner gives no task to someone in my group.**
Either they do not use Campkeeper (then their professions are unknown), or their professions cannot add anything the camp does not have yet.

**I found a bug.**
Open an [issue](https://github.com/Vikquick/Campkeeper/issues) and paste the output of `/ck debug`.
