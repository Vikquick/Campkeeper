# Campkeeper — тексты для CurseForge и Wago

Логотип: `docs/media/logo.png` (512×512, собственная графика; пересобрать: `python tools/make_logo.py`).
Исходники и баг-трекер: https://github.com/Vikquick/Campkeeper

## Поля формы

| Поле | Значение |
|---|---|
| Project name | Campkeeper |
| Summary (EN, одна строка) | Campsite companion: camp panel and timers, a shared map of camps, a catalog of camp objects, a group planner and an alts overview. |
| Main category | Professions |
| Additional categories | Map & Minimap; Buffs & Debuffs; Guild |
| Allow Comments | да |
| Unlisted | нет |
| Social links | GitHub: https://github.com/Vikquick/Campkeeper (Issues — https://github.com/Vikquick/Campkeeper/issues) |
| Wiki | https://github.com/Vikquick/Campkeeper/wiki (страницы — `docs/wiki/`, публикация — `python tools/sync_wiki.py`) |
| Issues URL | https://github.com/Vikquick/Campkeeper/issues |
| Donation method | No donation method (Boosty в списке нет); ссылка https://boosty.to/vikquick21/donate — в описании и на главной вики |
| Enable Project Pages | да: страница Roadmap (текст ниже) |
| Game version | World of Warcraft: Forever (Interface 16001) — сборщик проставит сам |

## Description (EN)

**Campkeeper** is a companion for the camping system of *World of Warcraft: Forever*: campfires, profession camp objects and the one-hour Camp Benefits buff.

### Camp panel
- Appears next to your buffs when you are near a camp and hides again when you leave (and always in combat).
- Shows the campfire, used and free places, and when your own fire goes out.
- Lists the objects already in the camp with their effect, and the objects **you** can add right now: one click places the item from your bags (out of combat).
- Marks objects whose bonus does not stack with a class buff you already have.
- Sitting countdown and the time your Camp Benefits end.

### Timers and alerts
- Shared cooldown of camping items — for every character of your account.
- Optional alerts: camp nearby, benefits received, benefits ending in 5 minutes, cooldown ready, your campfire going out.

### Camps on the map
- Your own camps and camps you used appear on the world map and the minimap; click a pin for a waypoint (TomTom supported).
- Camps are shared with your guild, your group and an optional shared channel. Reports from strangers are shown faded until a second player confirms them.

### Catalog, planner, alts (`/ck`)
- **Catalog:** every camp object by profession and tier, required skill, what it replaces, and which ones you can craft.
- **Planner:** who in your group places the fire and which objects — one item per member, class buffs in the group taken into account — and post the plan to group chat.
- **Alts:** professions, camping items, recipes and the cooldown of all your characters.

### Commands
- `/ck` or `/campkeeper` — open the window
- `/ck config` — settings
- `/ck debug` — diagnostic log (please attach it to bug reports)

Campkeeper is in **alpha** while *Forever* is in beta. Object names come from your game client, so it works in every language; the interface is in English and Russian.

Bugs and ideas: https://github.com/Vikquick/Campkeeper/issues

Guide to camping in Forever and every camp object: https://github.com/Vikquick/Campkeeper/wiki

Like Campkeeper? You can support it on Boosty: https://boosty.to/vikquick21/donate

## Описание (RU)

**Campkeeper** — помощник для системы лагерей *World of Warcraft: Forever*: костры, объекты профессий и часовой бафф «Бонусы лагеря».

- **Панель лагеря** рядом с баффами: костёр, свободные места, когда погаснет ваш костёр; что уже стоит и что можете поставить вы — одним кликом из сумок (вне боя); отметка, если бонус перекрыт классовым баффом; отсчёт сидения и время окончания бонусов.
- **Таймеры и оповещения:** общая перезарядка походных предметов по всем персонажам; оповещения о лагере рядом, полученных и заканчивающихся бонусах, готовой перезарядке и гаснущем костре.
- **Лагеря на карте:** свои и посещённые лагеря на карте мира и миникарте, путевая точка по клику (поддерживается TomTom); обмен с гильдией, группой и необязательным общим каналом, чужие сообщения подтверждаются вторым игроком.
- **Окно `/ck`:** каталог объектов по профессиям и тирам; планировщик «кто что ставит» с учётом классовых баффов и одного предмета на участника; альты с профессиями, предметами, рецептами и перезарядкой.

Команды: `/ck` (`/campkeeper`), `/ck config`, `/ck debug`. Статус — альфа на время беты *Forever*.

Справка по лагерям и всем объектам: https://github.com/Vikquick/Campkeeper/wiki

Поддержать разработку: https://boosty.to/vikquick21/donate

## Project Page «Roadmap» (CurseForge)

Тот же текст, что `docs/wiki/Roadmap.md`, — при изменении правим оба.

| When | Stage | What it brings |
|---|---|---|
| October 2026 | **Alpha** | Camp panel, timers and alerts, checked in the *Forever* beta. |
| End of October 2026 | **Beta** | Camps on the map and sharing with guild, group and the shared channel, checked with several players. |
| 4 November 2026 | **1.0** | Release together with *Forever*: catalog, planner and alts window checked on the live game. |
| After launch | Updates | The catalog follows game patches; fixes from your reports. |

Ideas and wishes are welcome in issues: https://github.com/Vikquick/Campkeeper/issues
