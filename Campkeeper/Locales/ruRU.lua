local L = LibStub("AceLocale-3.0"):NewLocale("Campkeeper", "ruRU")
if not L then return end

-- Slash commands
L["Commands:"] = "Команды:"
L["/camp - open the Campkeeper window"] = "/camp — открыть окно Campkeeper"
L["/camp config - open settings"] = "/camp config — открыть настройки"
L["/camp debug [all||clear] - show the debug log"] = "/camp debug [all||clear] — показать отладочный журнал"
L["Debug log: %d records"] = "Отладочный журнал: записей — %d"
L["Debug log cleared."] = "Отладочный журнал очищен."

-- Options
L["General"] = "Общие"
L["Show camp panel"] = "Показывать панель лагеря"
L["Show the camp panel next to your buffs while you are near a camp."] = "Показывать панель лагеря рядом с баффами, когда вы у лагеря."
L["Show minimap button"] = "Показывать кнопку у миникарты"
