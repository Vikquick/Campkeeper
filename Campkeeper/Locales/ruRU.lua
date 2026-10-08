local L = LibStub("AceLocale-3.0"):NewLocale("Campkeeper", "ruRU")
if not L then return end

L["Loading..."] = "Загрузка…"

-- Slash commands
L["Commands:"] = "Команды:"
L["/ck - open the Campkeeper window"] = "/ck — открыть окно Campkeeper"
L["/ck config - open settings"] = "/ck config — открыть настройки"
L["/ck debug [all||clear] - show the debug log"] = "/ck debug [all||clear] — показать отладочный журнал"
L["Debug log: %d records"] = "Отладочный журнал: записей — %d"
L["Debug log cleared."] = "Отладочный журнал очищен."

-- Options
L["General"] = "Общие"
L["Show camp panel"] = "Показывать панель лагеря"
L["Show the camp panel next to your buffs while you are near a camp."] = "Показывать панель лагеря рядом с баффами, когда вы у лагеря."
L["Show minimap button"] = "Показывать кнопку у миникарты"
