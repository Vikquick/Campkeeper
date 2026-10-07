# Ниши для аддонов WoW Forever (исследование от 2026-10-08)

## Рынок
- CurseForge, фильтр Forever (`gameVersionTypeId=88568`): ~3 750 проектов; ~1 200–1 600 сделаны только под Forever (оценка). Wago (`?game_version=forever`): 612.
- Большинство Forever-аддонов — мелкие клоны с < 1K загрузок; по популярным идеям по 10+ клонов.

## Занято (не берём)
Квесты/гайды (Questie, Guidelime, RestedXP, Joana's), альты (Altoholic Forever v1.60.004 от 2026-10-07), профессии (6+), LFG (38),
угроза (ForeverThreat, ThreatPlates и др.), замена WeakAuras (ForeverAuras, EllesmereUI), UI-наборы, комбо-поинты (14+), осколки душ (8+),
патроны/питомцы (20+), мировые баффы (11 мелких; в рейдах баффы, по сообщениям, отключены), Legacy (4 аддона), репутации, цены.

## Пробелы (по убыванию)
| # | Ниша | Почему | Риск |
|---|---|---|---|
| 1 | Компаньон лагерей (campsites) | Флагманская система Forever; аналоги: AzerothArchive Campsite Tracker (~17 загрузок), S'more Skills (~907, разработка на паузе), CampFirePin (42) | Обмен лагерями требует массовой установки |
| 2 | Хардкор-набор (лента смертей а-ля Deathlog) | Deathlog/DeathNotificationLib — только Classic/TBC; хардкор выходит «зимой» | Правила Forever не опубликованы; автор Deathlog может портировать |
| 3 | Данные новых зон и квестов 30–60 | Поиск «riverglades»/«hyjal» — 0 проектов; Questie на Classic-данных | Контент после 30 недоступен до запуска; большой объём данных |
| 4 | Ранги PvP и прогресс чести | 14 рангов без затухания; WarLedger — 16 загрузок | Неясно, что даёт API по чести других игроков |
| 5 | Планировщик Legacy | 65 испытаний; крупнейший аддон — 1,5K | Средняя ценность |

## Факты API (дамп клиента 1.60.1)
- Обмен аддонов: `C_ChatInfo.SendAddonMessage`, `CHAT_MSG_ADDON` без secret-флагов; есть `C_ChatInfo.InChatMessagingLockdown()` и
  `AreOutgoingAddonChatMessagesRestricted()` — в некоторых ситуациях (вероятно, бой с боссом) исходящие сообщения ограничены.
- Хардкор: `HARDCORE_DEATHS(memberName)` (только имя), `C_GameRules.IsHardcoreActive()`, строки причин смерти `HARDCORE_CAUSEOFDEATH_*`.
- `CHAT_MSG_SYSTEM` помечен `SecretInChatMessagingLockdown`.

## Источники
- https://foreverchanges.pro/addons , https://wow4ever.quest/en/addons
- https://www.warcrafttavern.com/forever/guides/camping/
- https://www.curseforge.com/wow/addons/azerotharchive-campsites
- https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-october-1/2360696
- https://eu.forums.blizzard.com/en/wow/t/my-required-addons-for-wow-forever/633300
- https://www.curseforge.com/wow/addons/altoholic
- https://www.icy-veins.com/wow-forever/pvp-rank-system
