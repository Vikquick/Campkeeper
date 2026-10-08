local L = LibStub("AceLocale-3.0"):NewLocale("Campkeeper", "ruRU")
if not L then return end

L["Loading..."] = "Загрузка..."

-- Slash commands
L["Commands:"] = "Команды:"
L["/ck - open the Campkeeper window"] = "/ck - открыть окно Campkeeper"
L["/ck config - open settings"] = "/ck config - открыть настройки"
L["/ck debug [all||clear] - show the debug log"] = "/ck debug [all||clear] - показать отладочный журнал"
L["Debug log: %d records"] = "Отладочный журнал: записей - %d"
L["Debug log cleared."] = "Отладочный журнал очищен."

-- Options
L["General"] = "Общие"
L["Show camp panel"] = "Показывать панель лагеря"
L["Show the camp panel next to your buffs while you are near a camp."] = "Показывать панель лагеря рядом с баффами, когда вы у лагеря."
L["Show minimap button"] = "Показывать кнопку у миникарты"

-- Minimap button
L["Left click: open window"] = "Левый клик: открыть окно"
L["Right click: settings"] = "Правый клик: настройки"

-- Alerts
L["Alerts"] = "Оповещения"
L["Camp nearby"] = "Лагерь рядом"
L["Benefits received"] = "Бонусы получены"
L["Benefits ending soon"] = "Бонусы скоро закончатся"
L["Camping cooldown ready"] = "Походные предметы снова готовы"
L["Own campfire going out"] = "Свой костёр гаснет"
L["A camp is nearby: sit by the fire for its benefits."] = "Рядом лагерь: сядьте у костра, чтобы получить бонусы."
L["Camp benefits received."] = "Бонусы лагеря получены."
L["Camp benefits end in 5 minutes."] = "Бонусы лагеря закончатся через 5 минут."
L["Camping items are ready again."] = "Походные предметы снова можно использовать."
L["Your campfire goes out in 1 minute."] = "Ваш костёр погаснет через 1 минуту."

-- Camp panel
L["Camp"] = "Лагерь"
L["Campfire goes out in %s"] = "Костёр погаснет через %s"
L["Camping cooldown: %s"] = "Перезарядка походных предметов: %s"
L["placed"] = "стоит"
L["click to place"] = "нажмите, чтобы поставить"
L["covered by a class buff"] = "перекрыто классовым баффом"
L["Sit by the fire to get the camp benefits"] = "Сядьте у костра, чтобы получить бонусы"
L["Stay seated: %d s"] = "Сидите ещё %d с"
L["Benefits until %s"] = "Бонусы до %s"
L["Camping items are on cooldown: %s"] = "Походные предметы на перезарядке: %s"
L["Too close to another object or creature."] = "Слишком близко к другому объекту или существу."

-- Map pins
L["Age: %s"] = "Возраст: %s"
L["Goes out in: %s"] = "Погаснет через: %s"
L["Source: %s"] = "Источник: %s"
L["your camp"] = "ваш лагерь"
L["seen by you"] = "вы были здесь"
L["group"] = "группа"
L["guild"] = "гильдия"
L["shared channel"] = "общий канал"
L["Unconfirmed: reported by one player"] = "Не подтверждён: сообщил один игрок"
L["Click: set a waypoint"] = "Клик: поставить путевую точку"

-- Sharing
L["Sharing"] = "Обмен"
L["Share camps in the shared channel"] = "Обмениваться лагерями в общем канале"
L["Guild and group sharing always stay on."] = "Обмен в гильдии и группе работает всегда."
L["Someone uses an incompatible Campkeeper version. Please update the addon."] = "У кого-то несовместимая версия Campkeeper. Обновите аддон."

-- Planner
L["Camp plan:"] = "План лагеря:"
