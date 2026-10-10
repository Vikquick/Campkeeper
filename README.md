# WoW Forever — разведка API

Клиент Forever (бета): `<папка WoW>\_classic_beta_` (`WowB.exe`, продукт `wow_classic_beta`, 1.60.1).
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

## 6. Campkeeper: разработка

Аддон лежит в `Campkeeper/`, план работ — в `openspec/changes/add-campkeeper/tasks.md`.

Библиотеки (Ace3, HereBeDragons, LibDBIcon и др.) в git не хранятся. Список — в `.pkgmeta`, при выпуске их встраивает BigWigs Packager, для разработки их скачивает скрипт (svn не нужен):

```
python tools/fetch_libs.py           — скачать недостающие в Campkeeper/Libs/
python tools/fetch_libs.py --force   — скачать всё заново
python tools/toc.py Campkeeper/Campkeeper.toc --check   — все ли файлы из .toc на месте
```

Тесты Lua вне игры (lupa, заглушки WoW API в `tests/wowmock.lua`):

```
python -m unittest discover tests
```

Подключение к клиенту беты (один раз, PowerShell):

```
New-Item -ItemType Junction -Path "<папка WoW>\_classic_beta_\Interface\AddOns\Campkeeper" -Target "<этот репозиторий>\Campkeeper"
```

В игре: `/ck` (или `/campkeeper`) — окно, `/ck config` — настройки, `/ck debug [all|clear]` — отладочный журнал (последние 200 записей, хранится в `CampkeeperDB`). Команду `/camp` занять нельзя: это встроенный выход из игры.

### Каталог лагерей после патча

`Campkeeper/Data/Catalog.lua` генерируется, руками не правится. Состав объектов, тиры, классовые баффы и веса планировщика — в `tools/catalog_tiers.json`; ID заклинаний генератор берёт из сканирования клиента.

1. В игре с включённым ForeverApiDump: `/fad scan camp`, дождаться «scan done», `/reload`.
2. Выгрузить раздел сканирования:
   ```
   python tools/fad.py json "<клиент>\WTF\Account\<АККАУНТ>\SavedVariables\ForeverApiDump.lua" --key scan -o out/scan.json
   ```
3. Пересобрать и проверить:
   ```
   python tools/gen_catalog.py
   git diff Campkeeper/Data/Catalog.lua
   python -m unittest discover tests
   ```

Генератор останавливается с ошибкой, если предмета из таблицы нет в сканировании, навык не совпал или сдвинулся порядок объектов (это порядок битов в протоколе обмена — новые объекты только в конец). `python tools/gen_catalog.py --check` проверяет, что закоммиченный каталог актуален.

### Вики

Страницы вики для игроков лежат в `docs/wiki/` (английский) и публикуются в GitHub Wiki репозитория. `docs/wiki/Camp-Objects.md` генерируется из `Campkeeper/Data/Catalog.lua` и `tools/wiki_objects.json` (английские названия и эффекты); после правки каталога:

```
python tools/gen_wiki.py             — пересобрать страницу объектов
python tools/sync_wiki.py --dry-run  — что изменится в вики
python tools/sync_wiki.py            — опубликовать
```

Вики-репозиторий GitHub создаёт только после первой страницы, сохранённой в браузере (вкладка Wiki → Create the first page). Тест `tests/test_gen_wiki.py` падает, если страница объектов устарела или у нового объекта нет текста.

## Лицензия

Campkeeper распространяется по лицензии MIT (`LICENSE`). Встроенные библиотеки в `Campkeeper/Libs` (Ace3, CallbackHandler, LibStub, HereBeDragons, LibDataBroker, LibDBIcon) — под своими лицензиями.
