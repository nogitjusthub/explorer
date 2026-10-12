# Explorer — архитектура проекта

**Версия:** 0.1 · **Дата:** 2026-10-07
**Движок:** Godot 4.7.2 stable, GDScript, рендерер Compatibility (ПК и веб).
**Дизайн:** [GDD.md](GDD.md) v0.2.

Документ описывает устройство кода: модули, данные, порядок обновления, рендер и тесты. Решения, проверенные по официальной документации Godot, отмечены ссылками в конце.

---

## 1. Принципы

1. **Веб с первой вехи.** Рендерер Compatibility (WebGL2) везде; веб-сборка без потоков. Всё тяжёлое (генерация, мешинг) — порциями по кадрам с бюджетом времени. Потоки на десктопе — возможная оптимизация позже, архитектура от них не зависит.
2. **Чистая логика отдельно от сцены.** Генерация, правила рельефа, кинематика, счёт — классы без доступа к дереву сцены. Их можно тестировать headless.
3. **Детерминизм.** Всё случайное — от `seed` забега и координат. Глобальный `randf()`/`randi()` запрещён.
4. **Data-driven баланс.** Числа живут в `.tres`-ресурсах, а не в коде.
5. **Без god-объектов.** Синглтонов три, и ни один не хранит состояние забега.

---

## 2. Структура папок

```
explorer/
├─ project.godot
├─ .gitignore  .gitattributes  README.md
├─ docs/                        GDD.md  ARCHITECTURE.md
├─ tools/                       .gdignore — Godot не сканирует папку
│  ├─ godot/                    портативный движок (в .gitignore), файл ._sc_ — self-contained режим
│  └─ scripts/                  get_godot  get_templates  test  export_web (.ps1), web_server.py
├─ src/                         код и сцены, сгруппированы по фичам
│  ├─ core/                     event_bus  balance  settings  job  job_scheduler  grid  det_rng
│  ├─ main/                     main.tscn (GameFlow)  run_state  leaderboard  drop_pod
│  ├─ terrain/                  chunk_data  terrain_data  terrain_rules  terrain_generator
│  │                            terrain_query  terrain_connectivity  terrain_repair  diff_store
│  │                            chunk_mesher  world_streamer  chunk_node  tree_field  (deformation — M3)
│  ├─ vehicle/                  vehicle  vehicle_models  vehicle_ride  vehicle_state  vehicle_kinematics  vehicle_input
│  ├─ camera/                   iso_camera_rig(.tscn)
│  ├─ hazards/                  threat_director  storm_front  weather_front  murk_layers  quake  tornado
│  ├─ fauna/                    fauna_director  creature  hopper_pack  worm  shellback  nest  noise_field  flow_field
│  ├─ pickups/                  pickup_generator  pickup_field
│  ├─ shuttle/                  shuttle_scheduler  emergency_call  shuttle_craft  shuttle_controller
│  ├─ render/                   terrain_materials  warmup  mesh_kit  shaders/ (terrain, water, tree, pickup, pickup_outline,
│  │                            fog_layer, fog_layer_depth, visibility.gdshaderinc, fog_layer.gdshaderinc)
│  ├─ audio/                    engine_sound  (audio_director — M3)
│  ├─ debug/                    dev_tools  autopilot  debug_snapshot  map_render  map_preview
│  └─ ui/                       debug_overlay  toast  weather_overlay  pause_overlay  ui_kit  vehicle_portrait
│                               hud/ (hud, radar, pager)  screens/ (hangar, help, shuttle_menu, results)
│                               screens/ (results_screen, shuttle_menu)
├─ data/                        ресурсы баланса (.tres)
│  ├─ balance_rules.gd  balance.tres  terrain_params.gd  terrain_params.tres
│  ├─ vehicles/                 vehicle_class.gd  rover.tres  tank.tres  hover.tres
│  └─ pickups/                  pickup_kind.gd  crystal  sample  core  repair  canister (.tres)
├─ assets/                      models/  textures/  sfx/  fonts/
└─ tests/                       run_tests.gd  test_case.gd  terrain_fixture.gd  unit/test_*.gd
```

**Соглашения:**

- Файлы и папки — `snake_case`; `class_name` и узлы — `PascalCase`; константы — `UPPER_SNAKE`; приватное — с `_`.
- Сигналы — глагол в прошедшем времени: `chunk_loaded`, `cargo_shipped`.
- Один `class_name` на файл; сцена лежит рядом со своим скриптом.
- Всё типизировано: параметры, возвращаемые значения, переменные.
- Идентификаторы — на английском, комментарии и документация — на русском.
- Скрипты `.ps1` сохраняются в UTF-8 с BOM: иначе Windows PowerShell 5.1 читает кириллицу как ANSI.

---

## 3. Модули

### 3.1 Чистая логика (без сцены, тестируется headless)

| Модуль | Ответственность |
|---|---|
| `Grid` | Константы (`CHUNK = 32`, `APRON = 1`, `TIER_H = 0.65` — визуальная высота яруса) и преобразования tile ↔ chunk ↔ world, индексы углов |
| `DetRng` | `hash(seed, a, b, stream) -> int`, `rng_for(...) -> RandomNumberGenerator` |
| `ChunkData` | Хранилище одного чанка (§4) |
| `TerrainRules` | Инварианты тайла (Δ ≤ 1), формы склонов, выбор диагонали, `relax()` |
| `TerrainGenerator` | seed + координаты чанка → `ChunkData`; все решения от мировых координат |
| `DiffStore` | Изменения поверх процедурной базы: тайлы и собранные находки |
| `TerrainData` | Реестр загруженных чанков; применение diff при загрузке; запись правок во все чанки-владельцы; dirty-секции |
| `TerrainQuery` | Высота, нормаль, стенка, вода, материал в точке и на ребре |
| `Deformation` | Воронка, борозда, разлом по углам тайлов загруженных чанков: общие вершины двигаются вместе, релаксация до Δ ≤ 1 (опускает высокие или поднимает низкие углы, неподвижные вершины площадок не трогает); у разлома — стенка вдоль линии и пандусы каждые 5 тайлов; вода затапливает опустившееся и уходит с поднятого; запись через `TerrainData.write_tile` |
| `ChunkMesher` | Секция чанка → массивы для `ArrayMesh` (верх, стенки, вода); `UV.x` верха — строка атласа пиксельных текстур (материал, неровный, зыбучий) |
| `TreeField` | Буфер `MultiMesh` деревьев чанка, занятость тайлов |
| `GroundSprites` | Мелочь на земле (M5): пиксельные спрайты травы, кустиков, камней, осколков в `MultiMesh` чанка (цвет и вид — в данных экземпляра); раскладка по хэшу тайла и материалу, высота — из углов тайла, буфер заливается целиком (≈1,4 мс на чанк на ПК); часть сборки `PART_SPRITES`, пересобирается с рельефом тайла (`DIRTY_SPRITES`) |
| `VehicleKinematics` | Один шаг движения по сетке над `VehicleState`; занос (`drift`), машина на подушке считает рёбра по зеркалу воды (`TerrainQuery.edge_rise_float_at`); зыбучий грунт — вязкий разгон и прилипание после стоянки (`mire_grip`, `VehicleState.mire_stuck`); предел скорости сверху `speed_cap` (пустой бак — ползком), круглые препятствия `obstacles` (корпуса севших челноков) |
| `RunState` | HP, топливо, трюм с вытеснением дешёвого, формулы счёта (сдача, аварийный вызов с заказом топлива и запчастей, бонус), итог забега |
| `Leaderboard` | `user://leaderboard.json`, топ-10 по классу |
| `PickupGenerator` | Находки чанка по правилам GDD §6: один `RandomNumberGenerator` на чанк, бросок на каждый тайл в фиксированном порядке (~0,2 мс на чанк); ремкомплект — на чанк |
| `ShuttleScheduler` | Расписание основного челнока: интервалы и дистанции посадок, анонс площадки за 30 с, окно 20 с с удержанием, пока открыто меню, вылет сразу после сдачи (`depart`); выбор площадки по дистанции |
| `EmergencyCall` | Аварийный челнок: заказ (топливо и запчасти), таймер прилёта, ожидание в небе, пока нет места; выбор тайла посадки (ровный, сухой, без стенок, в 2–4,5 тайла от машины); заказ по умолчанию по нужде |
| `NoiseField` | Шум машины (по скорости) и шумных событий (посадки челноков) — кто кого слышит |
| `FlowField` | Поиск пути фауны: поле расстояний (обход в ширину) до тайла машины в окне 61×61 по рёбрам, проходимым для вида (скакуны — только склоны и сушь, панцирник — как танк); строится задачей JobScheduler, одно поле на всех зверей вида |

### 3.2 Узлы сцены

| Узел | Ответственность |
|---|---|
| `JobScheduler` | Очередь задач с приоритетом и бюджетом микросекунд на кадр |
| `WorldStreamer` | Какие чанки нужны, гистерезис загрузки и выгрузки, пул `ChunkNode`; `ready_around` — мир вокруг точки собран и ямы залиты. При обычном старте мир вокруг точки старта грузится в фоне, пока игрок в трюме (бюджет задач там 12 мс); «Высадка» раньше, чем догружен мир и прошёл прогрев шейдеров, — трюм держит затемнение с надписью «загрузка мира…». Синхронно (`preload_around`) — только отладочные запуски и «Заново» |
| `ChunkNode` | 4 × `MeshInstance3D` (секции) + вода + `MultiMeshInstance3D` деревьев и мелочи на земле |
| `Vehicle` | Владеет `VehicleState`, вызывает кинематику, шлёт события; `set_class()` меняет модель и тон двигателя. Разряд по машине рисует `ShockFx`: ломаные дуги лентами к камере (`ImmediateMesh`) и белое мерцание корпуса через `material_overlay` — материалы с ключами, которые уже прогреты |
| `MeshKit` | Low-poly геометрия с плоскими гранями: призмы по контуру, правильные многоугольники, треугольники с правильной лицевой стороной — для техники и фауны; `face_mapped` — разметка граней для узора обшивки (UV — точка относительно центра грани, UV2 — её полуразмеры, `COLOR` и `CUSTOM0` — деталь грани) |
| `VehicleModels` | Модели трёх классов из примитивов по `design_references/`: коробки, цилиндры, трубы `_rod` (бампер, кенгурятник), призмы `MeshKit.prism` по контуру (нос ховера, гусеницы танка); материалы для силуэта (stencil; окрашенные части и гусеницы — `BodyMaterial` с узором), вращающиеся части, огонёк антенны `beacon` (`Vehicle` мигает им, пока летит аварийный челнок). Ходовая — в `root`, корпус — в подрессоренном `body`, антенна — на шарнире `antenna`. `build_plain` — без stencil, для экранов вне игры |
| `VehicleRide` | Анимация хода, только модель: тряска `body` (сумма синусов; по скорости, грунту `FLAG_ROUGH`/`FLAG_MIRE` и массе класса), осадка в зыбучем, наклоны от ускорения, колыхание и крен ховера, антенна-хлыст на пружине (инерция, отставание от раскачки `Vehicle.rock`) |
| `VehicleInput` | Действия ввода → вектор направления относительно экрана |
| `IsoCameraRig` | Ортокамера, поворот 90°, упреждение, тряска |
| `GameFlow` (`main.gd`) | Машина состояний: Старт → Десант → Вылазка → Итог; владеет `RunState`. Точка высадки — `_landing_point` рядом с площадкой старта (детерминированно по seed); `RunState.tick` и угрозы идут только в фазе вылазки |
| `DropPod` | Сцена десанта: тень и маркер на земле, капсула падает с разгоном и у земли тормозит тремя двигателями (пламя, подсветка, пыль, рёв `Sfx.thrust`), мягко садится (`landed` — тряску и испуг фауны делает `GameFlow`, глухой удар — `AudioDirector`), раскрывается лепестками (`opened` — старт вылазки) |
| `PauseOverlay` | Пауза по Esc: `get_tree().paused`, затемнение и надпись; включена только во время вылазки. `DevTools` работает и на паузе (`PROCESS_MODE_ALWAYS`) |
| `HangarScreen` | Экран выбора — трюм челнока в своём мире (`SubViewport`, `own_world_3d`): задняя и левая стены, люки в ряд вдоль задней стены, три модели (`VehicleModels.build_plain` — без x-ray), прожектор без теней (`SpotLight3D` + видимый конус, под машиной — пятно-тень) и лампа отсека над выбранной, характеристики значками; старт — машина уходит в люк, затемнение, `started` |
| `HelpScreen` | Справка F1 (`PROCESS_MODE_ALWAYS`): цель, угрозы, управление; во время вылазки ставит паузу. Статический `is_open` — пока справка открыта, другие экраны ввод не берут |
| `UiKit` | Кнопки с хоткеем (мышь и тап), текст с тенью, значки и шкала характеристик `stat_*` класса |
| `VehiclePortrait` | Маленький вращающийся портрет модели класса в своём мире (экран итога) |
| `ResultsScreen` | Итог, ввод имени (клавиши и тап), рекорды; кнопки «Заново [R]» (`Settings.quick_restart` — после перезагрузки сцены сразу десант) и «Выход [Esc]» (в трюм) |
| `ThreatDirector` | Уровень угрозы T, цикл непогоды «ясно → гроза или плохая видимость → ясно» (жребий вида — `murk_variant`), таймеры землетрясений и смерчей с T ≥ 3, затишье после сдачи; угрозы — дочерние узлы, урон машине — сигналом `damaged` |
| `StormFront` | Грозовой фронт: тень туч (глобальные `storm_center` / `storm_radius` / `storm_dark`), слои туч и зарницы, удары с весом по высоте, телеграф — «огни святого Эльма» (`st_elmo.gdshader`), ветвистые молнии со вспышкой света и искрами, урон, воронка, деревья, кристаллы, помехи радара; `weather_changed` — затемнение света и дождь |
| `WeatherFront` | Плохая видимость — масса (центр, радиус, рваный край), ползёт через машину. Вид — жребий: туман, кислотный туман (уровень газа по низинам, урон ниже него), пылевая буря (ветер в `ext_accel`, шанс смерча). Ставит глобальные `weather_*` и `vis_color`, шлёт `weather_changed` (свет, частицы) и сообщение пейджеру |
| `MurkLayers` | Объём непогоды: слои облачного шума (`fog_layer*.gdshader`) на разной высоте; плотность и край — из глобальных параметров погоды или грозы; дыра у машины сдвинута на высоту слоя, чтобы на экране совпасть с машиной; зарницы — подсветка слоёв |
| `WeatherOverlay` | Частицы на весь экран (CanvasLayer под HUD): косой дождь под грозой, пыль по ветру в буре |
| `Warmup` | Прогрев шейдеров на старте (пока игрок в трюме): отдельная камера (`SubViewport` с общим миром) снимает копии всего, что появится позже, — эффекты, существа, смерч, водоворот, челноки, капсула, все три машины; спрятанные части показаны, частицы летят; каждый образец — под точечным светом и без; образцы глубоко под миром, их материалы — в `ShaderCache`. Последним, когда мир догружен, — взгляд на настоящий рельеф у точки старта под светом и без. Высадка ждёт конца прогрева |
| `Tornado` | Смерч — сам по себе или из бури: блуждание с уклоном к машине (в буре — снос ветром), тяга `5 / масса × (1 − r/6)`, ядро 15/с и выброс по дуге туда, где посадка не выше, борозда (`Deformation.furrow`, скалы не берёт), вырванные деревья, подхваченные и разброшенные находки, гул по расстоянию |
| `Whirlpool` | Водоворот 2×2 тайла на глубокой воде (`fits`, `find_spot` по курсу машины): телеграф — круги и спираль пены (шейдер `whirlpool`), тяга к центру только по воде с закруткой (`pull`), ядро топит — `VehicleState.pull_under` (модель уходит в воду) и урон в секунду |
| `Quake` | Землетрясение: сила толчка → длина, сброс, пандусы; линия — ломаная 1–4 отрезка (`make_path`); телеграф (тряска, трещина, пыль по точкам линии, пейджер) — заодно порциями считает координаты зоны (`FaultLine.prepare`); толчок — `Deformation.fault_path` + осыпь `Deformation.mark_ground`; подброс машины, заливка ям |
| `FaultLine` | Линия разлома: координаты точки относительно ломаной (вдоль, поперёк со знаком, нормаль), кэш таких координат для зоны разлома по полуцелой сетке. На `Deformation` не ссылается — иначе цикл ссылок и утечка скриптов при выходе |
| `FaunaDirector` | Существа в кольце вокруг машины по уровню угрозы и биому, исчезновение вдали, троеглазки по чанкам, шум посадок, поля путей видов, урон машине — сигналом `damaged` |
| `Stargazer`, `MireShark`, `LakeMonster` | Водная фауна (GDD §5.6): троеглазка — донный шокер мелкой воды, по чанкам (`FaunaDirector._place_rays`), глаза — счётчик дистанции, разряд — урон и `Vehicle.invert_controls`, светящиеся части сдвинуты к камере над водой; илозуб — засадчик зыбуна (ареал — зыбучий грунт и вода рядом), путь по ареалу, замах с фиксацией цели, прыжок дугой, возврат ползком; Несса — озёрное чудовище больших озёр: путь по глубокой воде (обход в ширину), V-след и пузыри, всплытие, поза (направление удара фиксируется, на воде не отмечается), падение шеи, подброс ховера; V-след — шейдер `foam_strip` |
| `HopperPack`, `Worm`, `Shellback` | Стая скакунов (одна позиция на стаю, строй из 2–3 особей в тайле, патруль кольцом вокруг места появления, замечает машину зрением и на слух, укус — выпад переднего, отброс танком), песчаный червь (вал, кольцо трещин, бросок «как в Дюне» с тремя челюстями, яма; потерял интерес — пропадает), панцирник (подход без касания, рытьё, таран с отскоком, оглушение о стенку). Все — `Creature`: позиция на сетке, шаг движения с проверкой рёбер вида, потеря интереса `lost_interest` (fauna_give_up_s без продвижения к машине), трубы лап `rod`. Удары по машине — `Vehicle.rock` (раскачка модели), броски — `Vehicle.tumble` (наклон в полёте в сторону толчка) |
| `PickupField` | Находки загруженных чанков (по сигналам `chunk_built` / `chunk_removed` стримера), `MultiMesh` на вид, подбор, выпавшее из трюма, канистры по D(t) с запоминанием решения на чанк, запросы радара |
| `ShuttleController` | Связывает `ShuttleScheduler` и `EmergencyCall` с машиной, `RunState`, HUD: меню при остановке в зоне, после сдачи — вылет; радио (F — меню вызова, с воды — отказ); место посадки аварийного к началу спуска; касание — валка деревьев и раздавливание машины под корпусом (`crushed`); корпуса севших — препятствия в `VehicleState.obstacles`; обмен с аварийным; состояния для HUD |
| `ShuttleCraft` | Челнок из примитивов (основной — корпус-лофт по сечениям с фасками, треугольные крылья, киль, сопла — между шаттлом 70–80-х и челноками Star Trek; аварийный — коробки); звуки спуска, касания, взлёта и луча захвата — сигналом `EventBus.shuttle_sound`, играет `AudioDirector`: предупреждающий знак посадки (шейдер — круг с косыми полосами размером с корпус, мерцает чаще к касанию), спуск и посадка на землю, пыль, пунктир зоны погрузки, луч эвакуации из люка к машине, взлёт |
| `ShuttleMenu`, `EmergencyMenu`, `ResultsScreen` | Меню челнока (сдать груз / вернуться на орбиту); меню вызова аварийного (ползунок топливо ↔ запчасти, 30 ед. шагом 5, цена); итог забега, ввод имени, таблица рекордов |
| `Radar` | Часть HUD: находки и площадка (или стрелка на неё), ориентирован по экрану |
| `DevTools` | Параметры запуска, бенчмарк, снимки, сценарии без рук (`--idle`, `--press`) |
| `Visibility` | Глобальные uniform видимости, логическое скрытие объектов |
| `AudioDirector`, `Sfx` | Процедурные звуки событий (треск телеграфа молнии, гром, удар по корпусу, гудение помех при инверсии управления, фауна, челноки, «дзынь» подбора по `pickup_collected`, «би-бип» пейджера по `pager_alert`, гул пылевой бури по `weather_changed`), громкость по расстоянию. Синтез — по звуку за кадр, пока игрок в трюме (все сразу на старте — почти секунда чёрного экрана в браузере); нужный раньше синтезируется сразу |
| `HUD` | Отображение; подписан на `EventBus`, логики не содержит. Внутри — `Radar` и `Pager` (угрозы и «МАЛО ТОПЛИВА»: только название), вспышка экрана от молнии; внизу — таймеры челноков и при пустом баке мигающие «НЕТ ТОПЛИВА» / вызов аварийного |

### 3.3 Autoload-синглтоны

| Синглтон | Зачем |
|---|---|
| `EventBus` | Только сигналы, без состояния. Связи «один ко многим» (HUD, пейджер, аудио, тряска камеры) без ссылок между модулями |
| `Balance` | Загружает `data/*.tres`, отдаёт типизированный доступ: `Balance.vehicle(&"rover")`, `Balance.rules`. В тестах подменяется |
| `Settings` | Пользовательские настройки (тряска, зум, громкость), `user://settings.cfg` |
| `BodyMaterial` | Материалы техники и фауны с пиксельным узором (M5): `body.gdshader` (фауна) и `body_xray.gdshader` (техника — пишет 1 в stencil; силуэт сквозь препятствия — следующий проход `xray_pass`, как `STENCIL_MODE_XRAY`), общий код — `body.gdshaderinc`: цвет детали × яркость узора по координатам меша (траки, юбка, щитки, шкура, кольца, чешуя, ил, галька); обшивка техники — по граням: меш размечен `MeshKit.face_mapped`, грань делится на целое число пикселей, детали `Detail` (дверь, люк, решётка) — прямоугольники на своих гранях; свет — как у `StandardMaterial3D`. Цвет — параметр шейдера: `set_color` / `color_of` (годятся и для `StandardMaterial3D`) |
| `ShaderCache` | Держит материалы образцов прогрева всю сессию: шейдер `StandardMaterial3D` общий на набор свойств, и Godot выбрасывает его (с программами GPU) вместе с последним материалом — без удержания каждая молния и новый червь компилировали шейдеры заново. Переживает «Заново» |

**Правила шины:** по `EventBus` идут только уведомления. Тесные связи (машина ↔ рельеф) — прямые типизированные ссылки. Запросы с ответом через шину запрещены.

`RunState` — не синглтон: им владеет `GameFlow`, экран итога — дочерняя сцена, смены сцен нет. `JobScheduler` — узел под миром.

---

## 4. Данные рельефа

### 4.1 ChunkData

Чанк хранит **окно 34×34 тайла**: свои 32×32 плюс по одному ряду тайлов соседей (фартук). Фартук детерминированно совпадает с данными соседа, поэтому мешер рисует стенки на границе без доступа к соседним чанкам.

```gdscript
class_name ChunkData extends RefCounted
const N := 34                       # 32 + 2 × фартук
var coord: Vector2i
var corners: PackedByteArray        # N*N*4: ярус + 64; угол 0=NW(-x,-z) 1=NE 2=SE 3=SW
var material: PackedByteArray       # N*N: 0 грунт, 1 песок, 2 камень, 3 кристалл
var water_level: PackedByteArray    # N*N: 0 — нет воды, иначе ярус зеркала + 64
var trees: PackedByteArray          # N*N: 0 — нет; биты 0–5 тип, 6 повален, 7 выжжен
var tree_offset: PackedByteArray    # N*N: 4 бита x | 4 бита z (1/16 тайла)
var flags: PackedByteArray          # N*N: бит 0 площадка (не деформируется), 1 гнездо, 2 обломки
var biome: PackedByteArray          # N*N
var pickups: PackedInt32Array       # (local_index << 8) | kind
var dirty_sections: int             # битмаска: 4 секции 16×16 + вода + деревья
```

Размер — около 12 КБ на чанк; в памяти 25–49 чанков.

### 4.2 Диффы

- `DiffStore`: словарь «ключ тайла → полная запись тайла» (4 угла, материал, дерево, флаги). Ключ — упакованные мировые координаты: `(wx + 2^20) << 21 | (wz + 2^20)`.
- Ключ — тайл, а не угол: при стенке у вершины несколько высот, запись тайла однозначна.
- Операция над углом задаётся в мировых координатах вершины и разворачивается на тайлы вокруг неё. `TerrainData.write_tile()` пишет запись во внутреннюю область чанка-владельца и в фартуки до трёх соседних загруженных чанков, помечая их dirty.
- Собранные и вытесненные находки — там же: `removed_pickups`, `dropped_pickups`.
- Плотность канистр (зависит от времени, GDD §7.2) решается при **первой** загрузке чанка; результат записывается в diff, чтобы повторная загрузка дала то же самое.

### 4.3 Бесшовная генерация

- **Высота вершины** — чистая функция `f(x, z)` от мировых координат (ярусы), затем округление. Состав:
  - база — крупный шум с большой амплитудой и детальный шум;
  - горы — маска плюс широкие гребни;
  - одна ступенчатая функция по сумме «база + горы»: ширина подъёма между полками зависит от **скалистости** (горы, ущелья, выходы скал) — на скалах резко (обрывы), на грунте полого; в зонах пандусов и проездах ступеней нет;
  - ущелья — полоса вдоль изолинии шума с domain warp, вырезается вниз;
  - **дамбы** между водными областями с разными уровнями;
  - площадки челнока (выравнивание 5×5 и пологое кольцо) и чаши луж.
- **Седловины:** вершины считаются на окне с запасом в одну вершину (`EXT = 37`). Вершина — нижний угол седловидного тайла — поднимается на ярус, если ни один из её четырёх тайлов не станет круче яруса. Решение зависит только от вершин на расстоянии 1, поэтому одинаково во всех окнах.
- **Тайл** берёт углы из вершин. Разброс ≥ 2 — тайл уплощается до минимума (стенки на высоких рёбрах). Разброс 1 иногда тоже уплощается — уступ, вероятность растёт со скалистостью. «Кресты» на рёбрах при таком построении невозможны.
- **Вода:** уровень тайла — уровень его водной области (искривлённая решётка 192 тайла, уровень по хэшу области, ±1); в луже — уровень полки, если он выше. Дамбы гарантируют, что вода разных уровней не соприкасается; тест `test_no_hanging_water_and_few_saddles` проверяет, что вода нигде не висит над сухим соседом.
- **Лужи:** ячейки 22 тайла; место — ровная полка (36 проб высоты в трёх кольцах на одном ярусе), выше воды области, не на скалах.
- **Швов нет по построению:** окно чанка — это те же функции на тех же мировых координатах.
- **Против ям без выхода:** проезды (решётка коридоров с шагом 56, где всё пологое), обрывы только на выпуклостях, остаток — `TerrainRepair` (§4.4).
- **Этапы задачи генерации:** подготовка (площадки и лужи вокруг окна — по одной за шаг, это десятки проб высоты), вершины с запасом, правка седловин, тайлы. Каждый этап режется по рядам под бюджет кадра.

```gdscript
class_name TerrainGenerator extends RefCounted
func generate(coord: Vector2i) -> ChunkData                 # полный проход (тесты, предпросмотр)
func begin(coord: Vector2i) -> GenJob
func step(job: GenJob, deadline_usec: int) -> bool
func height_at(x: float, z: float) -> float                 # f(x, z) с площадками и лужами
func water_tier(tx: int, tz: int) -> int                    # уровень области или лужи
func pad_of_block(block: Vector2i) -> Vector3i              # (x, z, ярус) или z = NO_PAD
func puddle_of_cell(cell: Vector2i) -> Vector4              # (x, z, радиус, ярус) или NO_PUDDLE
```

Генерация — ~30 мс на чанк на ПК; подобрать параметры помогает `src/debug/map_preview.gd` (PNG-карта, §12), проверки качества — `TerrainChecks` (седловины, висящая вода).

### 4.4 Заливка ям и деформации

- **Заливка ям** (`TerrainRepair`). Окно 5×5 чанков вокруг центра загрузки обходится в обратную сторону: от выходов (граница окна и тайлы рядом с незагруженными чанками) по рёбрам без подъёма. Каждая недостижимая компонента поднимается до уровня самого низкого края. Тайлы вне ямы не меняются, поэтому новых ям не появляется. Правки идут через `TerrainData.write_tile` — во все окна чанков и в `DiffStore`.
- `WorldStreamer` запускает `PitFillJob` порциями после того, как генерация вокруг закончилась. До 4 проходов, пока есть изменения; изменённые секции пересобираются.
- По тестам на трёх seed'ах в окне 160×160 заливается меньше 2% тайлов; после заливки запертых тайлов нет.

- Воронка, борозда, валы: `raise/lower_corner` + `TerrainRules.relax()` до Δ ≤ 1 внутри каждого тайла — стенок не появляется.
- Разлом — единственная операция, создающая стенки. После него — локальная проверка связности и пандусы каждые 5 тайлов вдоль линии.
- Тайлы с флагом площадки не меняются; соседи релаксируют к их краю.
- `Deformation` возвращает список изменённых ключей тайлов → `TerrainData` → dirty-секции → `JobScheduler` пересобирает только их.

---

## 5. Меш, деревья, стриминг

### 5.1 ChunkMesher

- Прямые packed-массивы (`PackedVector3Array`, `PackedColorArray`, `PackedInt32Array`), предвыделенные через `resize()` и заполняемые по индексу, → `ArrayMesh.add_surface_from_arrays()`. Это быстрее `SurfaceTool` в GDScript: нет вызова на каждую вершину.
- Освещение плоское: нормаль грани считает фрагментный шейдер через `dFdx`/`dFdy`. Вершинные нормали в меше всё же есть (наклон тайла; у стенки — наружу): из них берётся смещение теней по нормали, без них грани затеняют сами себя («штриховка»). Верх — 4 вершины и 6 индексов на тайл, стенка — 4 вершины на ребро; признак стенки — в `COLOR.a`.
- Стенку рисует только более высокая сторона ребра — без дублей и без зависимости от соседнего чанка (данные фартука).
- 4 секции 16×16 на чанк; деформация пересобирает только затронутые секции.
- Сборка секции — ~0,5–0,8 мс на ПК (прямой доступ к байтам углов, оттенок тайла — дешёвый хэш координат), поэтому секция строится целиком за один шаг задачи; `BuildChunkJob` проверяет дедлайн между секциями.
- Вода — отдельный меш чанка: квады на уровне воды там, где он выше самого низкого угла тайла.

### 5.2 Деревья

`TreeField.build()` заполняет `MultiMesh` чанка через `set_instance_transform/color`: стволы, кроны двух типов (отдельные `MultiMesh`), поваленные стволы. На чанк — до сотни экземпляров, ~0,5 мс. Если понадобится быстрее — запись `MultiMesh.buffer` целиком. В Compatibility цвет и custom data экземпляра хранятся в half-float — идентификаторы туда не пакуем, типы деревьев — отдельные `MultiMesh`.

### 5.3 WorldStreamer и JobScheduler

- Кадр 480×320 при тайле 40 пикселей в ширину: ~12 ромбов по ширине (при 32 было ~15), на земле — след примерно 21×28 мировых единиц, повёрнутый на 45° → полудиагональ ≈ 18 тайлов.
- Радиус загрузки `R_load = 17 + 32 = 49` тайлов (чанк грузится, если его AABB пересекает круг) → сетка 5×5 чанков. Выгрузка — при `R_load + 32` (гистерезис).
- Центр круга — позиция машины + скорость × 2 с. Приоритет задачи — расстояние до центра.
- Пул `ChunkNode`: узлы и меши переиспользуются (`clear_surfaces()` + новая поверхность); при перемещении узла из пула — `reset_physics_interpolation()`.
- Худший случай — ховер (11 тайл/с) по диагонали: новый ряд из 5 чанков каждые ~3 с; укладывается при 6 мс на кадр.

```gdscript
class_name JobScheduler extends Node
var budget_usec: int = 4000          # веб: 6000
func enqueue(job: Job, priority: float) -> void   # Job: step(deadline_usec) -> bool, on_done()
```

---

## 6. Движение

```gdscript
class_name TerrainQuery extends RefCounted
func height_at(wx: float, wz: float) -> float                         # плоскость треугольника тайла
func normal_at(wx: float, wz: float) -> Vector3
func tile_corners(tx: int, tz: int) -> PackedByteArray                # 4 яруса; -1, если не загружен
func edge_step(from_tile: Vector2i, to_tile: Vector2i) -> int         # >0 стенка вверх, <0 вниз, 0 склон/ровно
func water_depth(tx: int, tz: int) -> int                             # в ярусах
func material(tx: int, tz: int) -> int
func has_tree(tx: int, tz: int) -> bool
func is_loaded(tx: int, tz: int) -> bool

class_name VehicleState extends RefCounted
# pos: Vector3, vel: Vector3, heading: float, falling: bool, fall_from_tier: int,
# uphill_tiles: int, ext_force: Vector3, tilt_basis: Basis

class_name VehicleKinematics
static func step(s: VehicleState, inp: Vector2, cls: VehicleClass,
        q: TerrainQuery, dt: float) -> StepResult   # inp — направление в мире, длина = газ
    # StepResult: fell_tiers, hit_wall, hit_tree, felled_tree, crossed_edge
static func fall_damage(cls: VehicleClass, h: int) -> int             # GDD §3.2
static func fuel_per_second(cls: VehicleClass, throttle: float) -> float
```

- Внешние силы (ветер бури, тяга смерча) источник кладёт в `state.ext_accel` (уже делённую на массу); кинематика копит их в сносе `push_vel`, который затухает сам (`PUSH_DAMP = 2`, при силе a снос выходит на a/2) и гасится стенками.
- Разгон с места может быть сильнее обычного (`launch_accel`, у танка 6): к 60% Vmax сходит к `accel`.
- Тормоза нет: без ввода машина замедляется с `brake_decel`. Целевая скорость — `max_speed × газ × max(cos(угол до нужного курса), 0)`; с места (скорость < 1) при угле больше 12° она 0 — машина доворачивает на месте и потом разгоняется. Танк (`turn_in_place`) стоит при угле больше 45° и на ходу.
- Сдвиг за шаг делится на под-шаги по пересечению рёбер тайлов.
- Перепад берётся в точке пересечения ребра (`edge_rise_at`, линейно между углами). Больше 1/3 яруса вверх — стенка: составляющая скорости поперёк ребра обнуляется, курс выравнивается вдоль стенки (скольжение). Больше 1/3 яруса вниз — падение.
- Падение: машина остаётся в пределах соседнего нижнего тайла, горизонтальная скорость ×0,5, приземление по высоте поверхности, урон `fall_damage`.
- Стенка проверяется передним краем машины (центр ± 0,3 тайла), падение — центром.
- Вода глубже допустимой для класса — не стенка: заехать или упасть можно, но машина переходит в состояние «тонет» (`drowning`): управления нет, скорость гаснет, машина опускается на дно и через `DROWN_TIME` (2 с) гибнет — `StepResult.drowned`, `EventBus.vehicle_died(&"drowned")`. Удар о воду урона не наносит. Ховер не тонет.
- Отладка: `--spawn=X,Z` — старт в точке мира, `--course=D` — автопилот едет строго по курсу.
- Наклон корпуса — из 4 точек контакта (`height_at` вокруг позиции), только для визуала.
- Внешние силы (смерч, ветер, толчки) накапливаются в `ext_force` и делятся на массу.

---

## 7. Данные баланса (Resource)

```gdscript
class_name VehicleClass extends Resource
@export var id: StringName
@export var display_name: String
@export var hp_max: int
@export var max_speed: float              # тайл/с
@export var accel: float                  # тайл/с²
@export var brake_decel: float
@export var turn_rate_deg: float
@export var turn_in_place: bool
@export var drift: float                  # боковое проскальзывание (ховер)
@export var mass: float
@export var uphill_loss_per_tile: float   # доля Vmax; танк 0
@export var uphill_floor: float           # 1/3
@export var downhill_accel_bonus: float   # 0.2
@export var max_water_depth: int          # -1 — любая (ховер)
@export var water_speed_mult: float
@export var hovers: bool
@export_enum("exp", "linear") var fall_damage_mode: String
@export var fall_damage_base: float       # 20 (exp) / 5 (linear)
@export var tree_fell_speed_frac: float
@export var tree_speed_after_frac: float
@export var tree_fell_damage: int
@export var fuel_max: float
@export var fuel_idle_per_min: float
@export var fuel_drive_per_min: float
@export var cargo_slots: int
@export var model: PackedScene
@export var engine_sound: AudioStream
```

Значения — из GDD §4: `rover.tres`, `tank.tres`, `hover.tres`.

| Ресурс | Ключевые поля |
|---|---|
| `BalanceRules` (`balance.tres`) | `drop_invuln_s = 3`; `radar_range = 40`; челнок: `shuttle_interval_base = 60`, `_step = 15`, `_max = 120`, `shuttle_dist_base = 25`, `_step = 15`, `_max = 70`, `shuttle_window_s = 20`, `shuttle_zone_r = 3`, `shuttle_stop_speed = 0.5`; аварийный: `emergency_delay_s = 10`, `emergency_supply = 30`, `emergency_supply_step = 5`, `emergency_land_min = 2`, `emergency_land_max = 4.5`, `emergency_cargo_mult = 0.5`, `emergency_penalty_base = 500`; пустой бак: `low_fuel_frac = 0.2`, `empty_crawl_speed = 0.4`; `shock_invert_s = 2`; бонус: `bonus_hp_mult = 3`, `bonus_fuel_mult = 2`; канистры: `canister_d0`, `canister_floor = 0.3`, `canister_fade_s = 600`; `calm_after_ship_s = 20`; кривая угрозы: `threat_time_step_s = 90`, `threat_dist_step = 500`, `threat_max = 6`; погода: `first_event_s`, `clear_t1_s`, `clear_t6_s`; землетрясения: `quake_min_level = 3`, `quake_interval_t3_s`, `quake_interval_t4_s`; гроза (`storm_*`, `strike_*`) и разлом (`fault_*`, `quake_toss_*`) — группы Storm и Quake |
| `ThreatConfig` (на угрозу) | `kind`, `telegraph_s`, `damage_center`, `damage_edge`, `radius`, `duration_min/max`, `speed`, `crater_depth`, `visibility_radius`, `wind_accel`, `pull_accel`, `min_threat_level`, `biome_weights`, звуки |
| `PickupKind` | `kind`, `slots`, `value`, `hp_restore`, `fuel_restore_min/max` (доля бака), `rarity`, `placement_rule` |
| `TerrainParams` | частоты и октавы fBm, порог ridge, амплитуда domain warp, `ledge_keep_p_plateau = 0.3`, `ledge_keep_p_plain = 0.1`, `water_noise_freq`, `tree_radius`, `pad_clear_r = 3`, `pad_size = 5` |

Канистра: `fuel_restore_min = 0.25`, `fuel_restore_max = 0.5`.

---

## 8. События (EventBus)

```gdscript
signal hp_changed(cur: int, max: int)
signal fuel_changed(cur: float, max: float)
signal fuel_empty()
signal cargo_changed(slots_used: int, slots_max: int, value: int)
signal score_changed(total: int)
signal vehicle_damaged(amount: int, source: StringName, at: Vector3)
signal vehicle_fell(h: int, dmg: int)
signal vehicle_died(cause: StringName)
signal pickup_collected(kind: StringName, value: int)
signal cargo_shipped(value: int, emergency: bool)
signal threat_telegraphed(kind: StringName, at: Vector3, seconds: float, dir_hint: Vector2)
signal threat_ended(kind: StringName)
signal weather_changed(kind: StringName, intensity: float)
signal terrain_deformed(tiles: PackedInt64Array)
signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)
signal shuttle_state_changed(state: StringName, seconds_left: float, pad: Vector3)
signal shuttle_menu_requested(open: bool)
signal emergency_state_changed(state: StringName, seconds_left: float, penalty: int)
signal camera_rotated(quarter_turns: int)
signal camera_shake_requested(strength: float, seconds: float)
signal run_started(seed: int, vehicle: StringName)
signal run_ended(result: Dictionary)
```

---

## 9. Порядок обновления

**`_physics_process`, 60 Гц.** Мир вызывает подсистемы явно, в фиксированном порядке — ради детерминизма.
Сейчас (M1): `GameFlow` (родитель, идёт первым) — фокус стримера, `RunState.tick`, подбор находок, расход топлива,
`ShuttleController.step`; затем `Vehicle` — шаг кинематики и сигналы урона и гибели. Целевой порядок:

1. `VehicleInput.sample(camera_yaw)`.
2. Погода и угрозы: таймеры, телеграфы, внешние силы → `state.ext_force`.
3. Фауна.
4. `VehicleKinematics.step` → события урона, падений, деревьев.
5. Находки, зона челнока, аварийный челнок.
6. Очередь деформаций → `TerrainData` → dirty-секции (меши здесь не трогаем).
7. `RunState.tick(dt)`: топливо, таймеры челнока, проверка HP = 0; пустой бак — машина ползёт (`Vehicle.out_of_fuel`).
8. `WorldStreamer.update_desired(predicted_pos)` — только обновляет очередь.

**`_process`:**

- `JobScheduler` выполняет задачи (генерация, мешинг секций, деревья) в пределах бюджета.
- `IsoCameraRig` следует за `vehicle.get_global_transform_interpolated().origin` + упреждение и привязывает позицию к пиксельной сетке рендера в плоскости экрана. У камеры `physics_interpolation_mode = OFF`.
- `Visibility` обновляет глобальные uniform.
- HUD обновляется только по сигналам.

---

## 10. Рендер в Compatibility

- **Пиксель-арт без шейдеров постобработки:** базовое разрешение 480×320 (`display/window/size/viewport_*`), окно 960×640, `stretch/mode = viewport`, `stretch/aspect = keep` (3:2 с полями), `stretch/scale_mode = integer`, фильтр холста `nearest`, MSAA выключен, шрифты без сглаживания. Камера: наклон 45°, `size = 320 × √2 / 40`, чтобы ромб тайла был 40 пикселей в ширину (≈ 28 в высоту); отладочный `--zoom=N`.
- **Тени:** одна ортогональная карта (`SHADOW_ORTHOGONAL`) на 40 единиц, `shadow_bias = 0.1`, `shadow_normal_bias = 2.0`; параметр запуска `--no-shadows` выключает их.

- **Террейн** (`terrain.gdshader`): `COLOR.rgb` — тинт материала, `COLOR.a` — признак стенки. Во `fragment()`: `NORMAL = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)))` с разворотом к камере — flat-освещение. Верх тайла — тонкая тёмная кромка по краям (сетка ромбов). Стенки — страты по `floor(world_y / 0.5)`, три цвета по кругу.
- **Пиксельные текстуры верха (M5):** атлас `assets/textures/terrain_tops.png` (6 строк по 64×64 текселя; клетка накрывает 4×4 тайла и бесшовна — периодический шум и ячейки Вороного, берётся по мировым XZ) генерирует `tools/textures/gen_terrain_tops.gd` (`godot --headless --path . --script res://tools/textures/gen_terrain_tops.gd`), его можно и перерисовать вручную. Текстура в оттенках серого: шейдер умножает цвет материала на значение × 1,5 — палитра и погода прежние. Импорт — без сжатия и мипмапов (`compress/mode=0`, `detect_3d/compress_to=0`), сэмплер — `filter_nearest`. Стенки обрывов — атлас `assets/textures/cliff_walls.png` (4 варианта по 16×10 текселей на тайл × ярус, `tools/textures/gen_cliff_walls.gd`): горизонталь — мировая координата вдоль стенки (ось выбирается по нормали грани), вертикаль — доля яруса, вариант — по хэшу места и яруса; множит цвет пласта по абсолютному ярусу. Вода — перебор палитры: `assets/textures/water_cycle.png` (16×16 на тайл, бесшовная, `tools/textures/gen_water_cycle.gd`) хранит фазу волны 0…7, `water.gdshader` сдвигает её со временем (4 шага в секунду) и берёт оттенок из палитры в 8 шагов; цвет по глубине — 4 ступени. Мелочь на земле — `assets/textures/ground_sprites.png` (8 спрайтов 8×8, `tools/textures/gen_ground_sprites.gd`, рисунки символами прямо в генераторе), `ground_sprite.gdshader`: цилиндрический билборд, отсечение по альфе, свет как у земли, без теней.
- **Видимость** (`visibility.gdshaderinc`): `global uniform vec3 vis_center; global uniform float vis_radius; global uniform vec4 vis_color;` → смешивание с цветом погоды по расстоянию в плоскости XZ, за радиусом — сплошной цвет. Глобальные uniform объявлены в `[shader_globals]` проекта и выставляются через `RenderingServer.global_shader_parameter_set()`.
- **Деревья** — `MultiMeshInstance3D` на чанк, `use_colors = true`.
- **Вода** — прозрачный меш чанка (`blend_mix`), цвет по глубине через vertex color, без чтения depth texture.
- **Силуэт за стеной** — `BaseMaterial3D.stencil_mode = STENCIL_MODE_XRAY` (stencil в Compatibility с Godot 4.5; помечен experimental). Запасной путь — `next_pass` с `render_mode depth_test_inverted, unshaded`. Проверить в браузере к концу M0.
- **Нет в Compatibility:** volumetric fog, SSR/SSAO/SSIL, декали, VoxelGI/SDFGI, TAA/FXAA/SMAA, DoF, GPU-частицы с trails и SDF-коллизиями, compute. Замены: телеграф-круги и маркер посадки — квад-меш, облегающий рельеф; частицы — `CPUParticles3D`; тени — одна `DirectionalLight3D`, в вебе по настройке; glow — только на десктопе.
- **Компиляция шейдеров** в Compatibility происходит при первом показе (программа на шейдер × проход × набор флагов) — в браузере на Windows (WebGL → ANGLE → Direct3D) это сотни миллисекунд на программу, первый червь вешал игру на ~2 с; на ПК программы кэшируются на диске, и этого не видно. Что учитывать:
  - Вариант зависит от того, задевает ли объект **точечный свет** (маячок, молния, знак удара, пламя капсулы, вспышка троеглазки): `Warmup` снимает каждый образец дважды — под светом и без.
  - Шейдер `StandardMaterial3D` живёт, пока жив хоть один материал с тем же набором свойств: образцы прогрева удаляются, поэтому их материалы держит `ShaderCache`. Иначе всё, что появляется и исчезает (молния, смерч, червь), компилировалось бы при каждом появлении.
  - Новый объект с новыми материалами — добавить его образец в `Warmup`. Проверка: `--shader-audit` печатает материалы с ключом шейдера, впервые появившимся после прогрева; на ПК пики компиляции видны только без дискового кэша — копия проекта с `override.cfg` (`rendering/shader_compiler/shader_cache/enabled=false`, другое `application/config/name`) и `--rendering-driver opengl3_angle`, кадры — по `--log-slow`.
- **Погода в шейдерах:** глобальные `vis_center`, `vis_color`, `weather_center` / `_radius` / `_clear` / `_gas_y` / `_max` / `_gloom`, `storm_center` / `_radius` / `_dark` (объявлены в `[shader_globals]`; необъявленный параметр — ошибка в консоли). `vis_hidden()` и `weather_grade()` — в `visibility.gdshaderinc`, их вызывают шейдеры рельефа, воды, деревьев и находок.

---

## 11. Тестирование

- `tests/run_tests.gd` (`extends SceneTree`) в `_init()` обходит `res://tests/unit/`, загружает `test_*.gd`, вызывает у каждого экземпляра методы с префиксом `test_`, печатает сводку и завершается с кодом 0 или 1. Фильтр — `-- --filter=<подстрока>`.
- `tests/test_case.gd` — базовый класс с `assert_eq`, `assert_true`, `assert_near`, `fail`; ошибки копятся в массив. Встроенный `assert` не подходит: работает только в debug и прерывает выполнение.
- Запуск — `tools/scripts/test.ps1` или напрямую:

```powershell
$g = ".\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
& $g --headless --path . --import
& $g --headless --path . --script res://tests/run_tests.gd
```

**Обязательные тесты M0:**

| Тест | Что проверяет |
|---|---|
| `test_generator_determinism` | Один seed и координаты → байт-в-байт одинаковые `ChunkData`; другой seed → отличаются |
| `test_seams` | Блок 3×3 чанка: фартук совпадает с областью соседа; у каждого тайла Δ углов ≤ 1; стенку на общем ребре рисует ровно одна сторона |
| `test_connectivity` | У каждой компоненты есть пандус наружу; на каждой стороне чанка ≥ 1 переход с `edge_step == 0` |
| `test_relax` | Воронка на плоскости — без стенок, тайлы валидны, площадка не изменилась; разлом создаёт стенки; diff при перезагрузке чанка воспроизводит рельеф |
| `test_fall_damage` | Таблица GDD §3.2 для трёх классов; h = 1 → 0 |
| `test_fuel` | Ровер: 60 с холостого = 3 ед., полный газ = 15, газ 0,5 = 9 |

---

## 12. Окружение и инструменты

| Задача | Команда |
|---|---|
| Скачать движок (SHA512) | `powershell -ExecutionPolicy Bypass -File tools\scripts\get_godot.ps1` |
| Шаблоны веб-экспорта (SHA512, только web без потоков) | `powershell -ExecutionPolicy Bypass -File tools\scripts\get_templates.ps1` |
| Редактор | `editor.cmd` (из любой папки) |
| Тесты | `powershell -ExecutionPolicy Bypass -File tools\scripts\test.ps1 [-Filter …]` |
| Игра | `play.cmd [--seed=N]` (из любой папки; прямой запуск exe с `--path .` работает только из корня проекта) |
| Бенчмарк (автопилот, ПК) | `… --path . -- --seed=7 --bench=40` (можно `--headless`) |
| Отладочный снимок в игре | **F12** на ПК (геймпад — Back; в веб-версии отключён — F12 открывает консоль браузера) → `build/debug/<дата_время>/`: `screenshot.png`, `map.png` (65×65 тайлов, машина — крест), `info.txt` (seed, коммит, команда воспроизведения, состояние машины, рёбра её тайла, сетка ярусов), `tiles.json` (дамп тайлов 17×17). В вебе — на `/shot` и `/log`. Без клавиатуры: `-- --snapshot-at=S` |
| Старт в точке / прямой курс | `play.cmd --seed=N --spawn=X,Z [--course=D --autopilot]` |
| Класс техники | `play.cmd --vehicle=tank` (rover, tank, hover); снимок экрана выбора — `-- --idle --select --shots=1` |
| Снимки экрана | `… --path . -- --seed=7 --shots=4 --shot-every=3` → `build/shots/` |
| Угрозы | `-- --no-threats`, `--no-fauna`, `--threat=N` (уровень не ниже N), `--event=storm@5,quake@12` (storm, quake, fog, acid, dust, tornado, hoppers, worm, shellback — событие на заданной секунде; разлом не ложится у площадки старта — для проверки `--spawn=100,60`). В отчёте бенчмарка — счётчики угроз; `--log-slow` печатает кадры дольше 20 мс со временем (первый запуск после правки шейдеров даёт пики компиляции — со второго их нет, Godot кэширует) |
| Сценарий без рук | `… -- --seed=7 --idle --shuttle-in=6 --shuttle-dist=0 --shots=2 --press=radio@8`: машина стоит на площадке старта, челнок садится через 6 с, F на 8-й секунде (меню открыто — подтверждает эвакуацию). Без стартового экрана (`--idle`, автопилот, бенчмарк) и с `--no-drop` сцены десанта нет — машина сразу на площадке старта; десант с экраном выбора: `--idle --select --press=radio@0.6 --shots=16 --shot-every=0.25`. Пауза: `--press=pause@3,pause@5`. Ещё: `--fuel=N` (мало топлива — проверка пустого бака), `--debug` (оверлей сразу) |
| Карта рельефа в PNG | `… --headless --path . --script res://src/debug/map_preview.gd -- --seed=1 --chunks=8` → `build/preview/` |
| Веб-сборка | `powershell -ExecutionPolicy Bypass -File tools\scripts\export_web.ps1 [-Debug] [-Serve]` → `build/web/` |
| Веб-сервер с приёмом отчётов | `python tools/scripts/web_server.py 8000`; страница `http://127.0.0.1:8000/?seed=7&bench=40&shots=2` пишет результаты в `build/web_log.txt` и снимки в `build/web_shots/` |

- Движок портативный, лежит в `tools/godot/` (в `.gitignore`), self-contained режим (`._sc_`) — настройки редактора и шаблоны экспорта внутри этой папки.
- `build/` в `.gitignore` и с `.gdignore` — Godot его не сканирует.
- Пресет `Web` в `export_presets.cfg`: однопоточная сборка (`variant/thread_support = false`), спец-заголовки сервера не нужны.

## 13. Подводные камни (найдены в M0)

- **Имя enum, совпадающее со встроенным классом** (`enum Material` в `ChunkData`), ломает разрешение типа `ChunkData.Material` — компиляция зависимых скриптов падает. Поэтому enum называется `Mat`.
- **Новый `class_name`** виден другим скриптам только после `--import`: Godot обновляет кэш глобальных классов при импорте. `test.ps1` делает импорт сам.
- **Headless-импорт иногда падает** с access violation (0xC0000005) сразу после правки скриптов или шейдеров; повторный запуск проходит. `test.ps1` делает до трёх попыток.
- **`--script` с ошибкой не завершается**: если `_initialize()` упал до `quit()`, процесс висит вечно. Ручные запуски — с таймаутом.
- **Типизация `:=`** не выводит тип из нетипизированного массива или выражения с `is` — нужен явный тип (`var pressed: bool = …`).
- **Windows PowerShell 5.1** читает `.ps1` без BOM в ANSI-кодировке — скрипты сохраняются в UTF-8 с BOM. Stderr нативной программы при `$ErrorActionPreference = "Stop"` превращается в прерывающую ошибку — в скриптах запуска Godot стоит `Continue`.
- **Веб: `localhost` против `127.0.0.1`.** Браузер может пойти по IPv6 (::1), а Python-сервер слушает только IPv4 — открывать `http://127.0.0.1:…`. Старый процесс на том же порту (Windows разрешает повторный bind) молча перехватывает запросы.
- **Веб-аудио** без жеста пользователя не стартует (`AudioContext was not allowed to start`); в бенчмарке без стартового экрана это ожидаемо.
- **Цикл ссылок `RefCounted`** (запись чанка ↔ её задача) не освобождается сам — ссылку на задачу обнуляем при выгрузке.

## 14. Риски

| Риск | Мера |
|---|---|
| Мешинг в wasm в 2–3 раза медленнее | Секции 16×16, возобновляемые задачи, предвыделенные packed-массивы, нормали в шейдере, никаких временных `Dictionary`/`Vector3` в горячих циклах; при нехватке — секции 8×32 |
| Рывки при стриминге | Гистерезис загрузки и выгрузки, приоритет по расстоянию и предсказанию, пул `ChunkNode` |
| Аллокации и сборка мусора | Пулы узлов и буферов, переиспользование `ArrayMesh`, запись `MultiMesh.buffer` целиком |
| Stencil экспериментальный | Запасной проход с `depth_test_inverted`; проверка в WebGL2 на M0 |
| Точность float вдали от нуля | За 10 минут ховер уезжает на ~6,6 км — приемлемо; целочисленные координаты в `Grid` оставляют возможность origin shift |
| Веб-аудио требует жеста | Стартовый экран «нажмите, чтобы начать»; геймпад в браузере активируется после первой кнопки |
| Детерминизм между платформами | Битовая идентичность ПК ↔ веб не гарантируется; тесты детерминизма — внутри одной платформы |
| Компиляция шейдеров в кадре | Прогрев материалов на стартовом экране |

---

## Источники

[godot-builds 4.7.2-stable](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable) ·
[Exporting for Web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html) ·
[Renderers](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) ·
[Spatial shader reference](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html) ·
[BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html) ·
[Stencil support, PR #80710](https://github.com/godotengine/godot/pull/80710) ·
[Advanced physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html) ·
[Command line tutorial](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) ·
[MultiMesh half-float в Compatibility, issue #96503](https://github.com/godotengine/godot/issues/96503) ·
[Project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)
