# Explorer

Изометрическая аркада на рекорд: высадись на живую чужую планету, набей трюм и выберись живым.
Godot 4.7.2, GDScript, рендерер Compatibility (ПК и веб).

**Играть в браузере:** https://nogitjusthub.github.io/explorer/ (обновить страницу после коммитов — `tools\scripts\publish_web.ps1`).

- Дизайн: [docs/GDD.md](docs/GDD.md)
- Архитектура: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Установка

Движок портативный и лежит в `tools/godot/` (в git не попадает). Скачать и проверить SHA512:

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\get_godot.ps1
```

В PowerShell 7 (`powershell` не находится) — так: `pwsh -ExecutionPolicy Bypass -File tools\scripts\get_godot.ps1`. После скачивания один раз импортировать проект (кэш классов в `.godot/` в git не попадает):

```powershell
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

Запустить игру — `play.cmd`, открыть редактор — `editor.cmd` (в корне проекта; двойной клик в Проводнике или из любой папки терминала).

> Если запускать exe напрямую с `--path .`, точка считается от **текущей папки терминала**. Из другой папки Godot не найдёт проект и откроет менеджер проектов.

## Тесты

Headless, без аддонов:

```powershell
powershell -ExecutionPolicy Bypass -File tools\scripts\test.ps1
powershell -ExecutionPolicy Bypass -File tools\scripts\test.ps1 -Filter smoke
```

Тесты лежат в `tests/unit/test_*.gd`, наследуют `TestCase`, методы называются `test_*`.

## Запуск и инструменты

```powershell
# Игра (W/A/S/D — движение, F — аварийный челнок, Q/E — камера, M — карта, Esc — пауза и настройки, F1 — справка, F3 — отладка). Параметры — play.cmd --help
.\play.cmd --seed=7

# Бенчмарк: автопилот 40 с, печать FPS, стриминга и расхода топлива
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path . -- --seed=7 --bench=40

# Карта рельефа в PNG (build/preview/) — для подбора параметров генератора
.\tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://src/debug/map_preview.gd -- --seed=1 --chunks=8

# Веб-сборка (build/web/) и локальный сервер: http://127.0.0.1:8000
powershell -ExecutionPolicy Bypass -File tools\scripts\get_templates.ps1        # один раз
powershell -ExecutionPolicy Bypass -File tools\scripts\build_web_template.ps1   # один раз: свой урезанный шаблон
powershell -ExecutionPolicy Bypass -File tools\scripts\export_web.ps1
python tools\scripts\web_server.py 8000

# Замер загрузки веб-сборки без окон (headless Chrome, холодный кэш): build/web_runs/<время>-full-1/summary.txt
node tools\scripts\web_bench.mjs --scenario full --assert
```

Release-экспорт идёт на своём шаблоне `tools/godot/templates/web_nothreads_release.zip` (`index.wasm` 39,5 → 22,2 МБ, в gzip 10,1 → 5,6 МБ): Godot собран из исходников без физики, сети, лишних форматов и классов, которых нет в игре. Исходники, Emscripten и объектники — вне репозитория, в `..\godot-web-build`; правки движка (`tools/web/godot_patches/`) накладываются при сборке — без них первая загрузка в браузере в несколько раз дольше. Без этого zip `export_web.ps1` берёт официальный шаблон. Что отключено и что делать, если игре понадобится, — [ARCHITECTURE.md](docs/ARCHITECTURE.md), §12.

**Нашёл баг в игре — нажми F12** (на ПК; в браузере F12 — консоль, снимка там нет). Снимок (скриншот, карта окрестностей, состояние машины, дамп тайлов и команда для воспроизведения) сохранится в `build/debug/<дата_время>/`.

Все команды и параметры — в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), §12.

## Структура

| Путь | Содержимое |
|---|---|
| `src/` | Код и сцены, сгруппированные по фичам (core, main, terrain, vehicle, …) |
| `data/` | Ресурсы баланса (`.tres`) |
| `assets/` | Пиксельные текстуры (их генерируют скрипты `tools/textures/`) и шрифт Ark Pixel 10 px; модели и звуки — процедурные, в коде |
| `tests/` | Раннер и юнит-тесты |
| `tools/` | Портативный движок, свой веб-шаблон, скрипты сборки и генераторы текстур (Godot их не сканирует — `.gdignore`) |
| `docs/` | Дизайн-документ, архитектура, варианты облика фауны, бэклог планет |
