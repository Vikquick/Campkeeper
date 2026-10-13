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
Between addons, invisibly: camps (where they are, which fire, which objects and when the fire goes out). Your guild and group get them always; the shared channel only if you turn it on. Your group also gets your profession skills, so the planner can give you a task.

In ordinary chat, visibly: only what you ask for. **Announce** posts one line about the camp you stand at, and the Planner buttons post the plan or the list of members without Camp Benefits. Campkeeper never writes to chat on its own.

**Can I announce a camp in English from a non-English client?**
Yes. Set *Language of announcements* in the settings to English (or Russian). Campkeeper carries its own English and Russian names of campfires and camp objects for this; other languages follow the language of your game. A few English names may differ slightly from the ones in the English game client.

**What is the code at the end of an announcement, like `(Campkeeper T1 7m #19ngg)`?**
It is for other players with Campkeeper: fire tier (`T1`), minutes left (`7m`) and the objects of the camp (`#19ngg`). Only what is known is written, so at a camp nothing is known about it is just `(Campkeeper)`. Thanks to it their addon understands your announcement even if it is written in a language they do not read.

**Does Campkeeper read my chat?**
It looks at chat lines that contain a map pin, to put camps other players talk about on your map. Nothing leaves your computer. Turn it off with *Read camps from chat* in the settings.

**Why is there a faded camp on my map that nobody in my guild reported?**
Someone posted a map pin with a word about a camp in chat. Such camps stay faded and disappear after 10 minutes unless a second player reports the same place or you get Camp Benefits there. A pin about something else that happens to mention a camp can show up the same way.

**What is `/ck report`?**
While *Forever* is in beta, Campkeeper can collect a few facts about camps (tooltip texts, aura timings, placement errors) to make the addon more accurate. They stay in your saved variables on your computer; nothing is sent anywhere. You can turn this off in the settings.

**The planner gives no task to someone in my group.**
Either they do not use Campkeeper (then their professions are unknown), or their professions cannot add anything the camp does not have yet.

**I found a bug.**
Open an [issue](https://github.com/Vikquick/Campkeeper/issues) and paste the output of `/ck debug`.
