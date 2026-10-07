# WoW Forever — разведка API

Клиент Forever на этой машине: `E:\wow\World of Warcraft\_classic_beta_` (`WowB.exe`, продукт `wow_classic_beta`, 1.60.1).
Аддон подключён junction-ссылками в `_classic_beta_` и `_retail_` → `Interface\AddOns\ForeverApiDump`.

## 1. Номер Interface

В игре: `/dump select(4, GetBuildInfo())` и `/dump WOW_PROJECT_ID`.
Если номер Forever не `16001`, поправьте `## Interface` в `ForeverApiDump/ForeverApiDump.toc`
(или включите «Загружать устаревшие модификации» на экране выбора персонажа).

## 2. Дамп (в обоих клиентах)

```
/fad dump          — снимок API (вне боя)
/reload            — клиент записывает файл
/fad events start  — запись реально срабатывающих событий (поиграть, потом stop + /reload)
/fad status
```

Файл появится в `WTF\Account\<АККАУНТ>\SavedVariables\ForeverApiDump.lua` каждого клиента.

## 3. Отчёты

```
python tools/fad.py report "<forever>\ForeverApiDump.lua" -o out/forever-reference.md
python tools/fad.py diff   "<forever>\ForeverApiDump.lua" "<retail>\ForeverApiDump.lua" -o out/forever-vs-retail.md
python tools/fad.py json   "<forever>\ForeverApiDump.lua" -o out/forever.json
```

В справочнике нестандартные поля документации (например, пометки Midnight о защищённых значениях)
выводятся рядом с сигнатурой — по ним видно, что недоступно в бою.

## 4. Код интерфейса Blizzard

Запуск `WowB.exe -console`, консоль клавишей `` ` ``, команды `ExportInterfaceFiles code` и `ExportInterfaceFiles art`.
Результат — папка `BlizzardInterfaceCode` рядом с клиентом (FrameXML и `Blizzard_APIDocumentationGenerated`).

## 5. Разведка лагерей

```
/fad camp start         — включить запись (ауры с подсказками, свои касты, vignettes, подсказки объектов, события)
/fad camp mark <заметка> — пометка в логе («поставил костёр», «сел»)
/fad camp stop          — выключить; затем /reload
```

Лог пишется в `ForeverApiDumpDB.camp.log` (до 6000 записей).

Тест инструментов без игры: `python tools/test_fad.py` (нужен `pip install --user lupa`).
