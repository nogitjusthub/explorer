@echo off
rem Запуск игры. Путь к проекту берётся от расположения этого файла, поэтому работает из любой папки.
rem Параметры передаются в игру как есть (разделитель «--» для Godot ставится здесь).
rem Справка: play.cmd --help
rem
rem Мир и машина
rem   --seed=N           задаёт мир (по умолчанию — от времени)
rem   --vehicle=ID       машина: rover, tank, hover (по умолчанию — последняя выбранная)
rem   --spawn=X,Z        старт в точке мира вместо площадки
rem   --no-drop          без сцены десанта: машина сразу на площадке старта
rem   --fuel=N           топлива в начале забега, единиц
rem Камера и экран
rem   --zoom=N           камера в N раз крупнее (0.75 — мельче)
rem   --no-shadows       без теней
rem   --debug            отладочный оверлей виден сразу (иначе — по F3)
rem Угрозы
rem   --no-threats       без угроз (погода, землетрясения, смерчи)
rem   --no-fauna         без фауны
rem   --threat=N         уровень угрозы не ниже N (1–6)
rem   --event=K@S,...    событие K на S-й секунде: storm, strike, fog, acid, dust, tornado,
rem                        quake, whirlpool, hoppers, worm, shellback, shark, ray, nessie
rem                        (strike — молния в машину; червь — если рядом песок или равнина;
rem                        водные — если рядом зыбун, мелкая или глубокая вода)
rem Сценарии без рук
rem   --idle             без стартового экрана и автопилота: машина стоит
rem   --select           показать трюм с выбором машины и при --idle или --shots
rem   --press=A@S,...    нажать действие A на S-й секунде: radio@8,move_right@9
rem   --click=X:Y@S,...  клик (тап) в точке X,Y рендера 480×320 на S-й секунде
rem   --shuttle-in=S     первый челнок садится через S секунд
rem   --shuttle-dist=D   площадка челнока на дистанции D (0 — площадка старта)
rem Автопилот, бенчмарк, снимки
rem   --autopilot        машина едет сама, гибель — возрождение
rem   --course=D         автопилот строго по курсу D градусов, без объезда
rem   --bench=S          бенчмарк S секунд с автопилотом, отчёт и выход
rem   --log-slow         печатать кадры дольше 20 мс: сколько заняли игра, генерация, отрисовка
rem                        (в вебе — ?log-slow в адресе, строки в консоли браузера F12)
rem   --shader-audit     печатать материалы с новым ключом шейдера, появившиеся после прогрева
rem                        (их шейдер прогрев не покрыл — первое появление дёрнет кадр в браузере)
rem   --shots=N          N скриншотов в build\shots, интервал --shot-every=S (3 с)
rem   --snapshot-at=S    отладочный снимок (как по F12) через S секунд

if /i "%~1"=="--help" goto :help
if /i "%~1"=="-h" goto :help
if "%~1"=="/?" goto :help
start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." -- %*
exit /b

:help
for /f "tokens=2 delims=:." %%a in ('chcp') do set "_oldcp=%%a"
chcp 65001 >nul
echo Запуск: play.cmd [параметры]   (из любой папки)
echo.
echo  Мир и машина
echo   --seed=N           задаёт мир (по умолчанию — от времени)
echo   --vehicle=ID       машина: rover, tank, hover (по умолчанию — последняя выбранная)
echo   --spawn=X,Z        старт в точке мира вместо площадки
echo   --no-drop          без сцены десанта: машина сразу на площадке старта
echo   --fuel=N           топлива в начале забега, единиц
echo.
echo  Камера и экран
echo   --zoom=N           камера в N раз крупнее (0.75 — мельче)
echo   --no-shadows       без теней
echo   --debug            отладочный оверлей виден сразу (иначе — по F3)
echo.
echo  Угрозы
echo   --no-threats       без угроз (погода, землетрясения, смерчи)
echo   --no-fauna         без фауны
echo   --threat=N         уровень угрозы не ниже N (1–6)
echo   --event=K@S,...    событие K на S-й секунде: storm, strike, fog, acid, dust, tornado,
echo                        quake, whirlpool, hoppers, worm, shellback, shark, ray, nessie
echo                        (strike — молния в машину; червь — если рядом песок или равнина;
echo                        водные — если рядом зыбун, мелкая или глубокая вода)
echo.
echo  Сценарии без рук
echo   --idle             без стартового экрана и автопилота: машина стоит
echo   --select           показать трюм с выбором машины и при --idle или --shots
echo   --press=A@S,...    нажать действие A на S-й секунде: radio@8,move_right@9
echo   --click=X:Y@S,...  клик (тап) в точке X,Y рендера 480×320 на S-й секунде
echo   --shuttle-in=S     первый челнок садится через S секунд
echo   --shuttle-dist=D   площадка челнока на дистанции D (0 — площадка старта)
echo.
echo  Автопилот, бенчмарк, снимки
echo   --autopilot        машина едет сама, гибель — возрождение
echo   --course=D         автопилот строго по курсу D градусов, без объезда
echo   --bench=S          бенчмарк S секунд с автопилотом, отчёт и выход
echo   --log-slow         печатать кадры дольше 20 мс: сколько заняли игра, генерация, отрисовка
echo                        (в вебе — ?log-slow в адресе, строки в консоли браузера F12)
echo   --shader-audit     печатать материалы с новым ключом шейдера, появившиеся после прогрева
echo                        (их шейдер прогрев не покрыл — первое появление дёрнет кадр в браузере)
echo   --shots=N          N скриншотов в build\shots, интервал --shot-every=S (3 с)
echo   --snapshot-at=S    отладочный снимок (как по F12) через S секунд
echo.
echo Примеры:
echo   play.cmd --vehicle=tank --seed=1                  танк, мир 1
echo   play.cmd --event=fog@3                            туман сразу; так же storm, acid, dust, tornado
echo   play.cmd --event=hoppers@3                        стая скакунов сразу атакует
echo   play.cmd --spawn=-43,-8 --seed=7 --event=worm@2   песчаный червь (старт на песке)
echo   play.cmd --spawn=100,60 --event=quake@5           землетрясение (у площадки старта разлома не бывает)
echo   play.cmd --idle --shuttle-in=6 --shuttle-dist=0   челнок на площадке старта через 6 с
echo   play.cmd --idle --fuel=0.1 --event=strike@3       пустой бак и молния в машину
echo.
echo В игре: W/A/S/D — движение, F — аварийный челнок, Q/E — поворот камеры, Esc — пауза, F1 — справка, F3 — отладка, F12 — снимок в build\debug
chcp %_oldcp% >nul
exit /b
