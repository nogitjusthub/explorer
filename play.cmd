@echo off
rem Запуск игры. Путь к проекту берётся от расположения этого файла, поэтому работает из любой папки.
rem Параметры передаются в игру как есть (разделитель «--» для Godot ставится здесь):
rem   play.cmd --seed=7 --zoom=4
rem Справка: play.cmd --help
rem
rem   --seed=N          задаёт мир (по умолчанию — от времени)
rem   --zoom=N          камера в N раз крупнее
rem   --spawn=X,Z       старт в точке мира вместо площадки
rem   --autopilot       машина едет сама
rem   --course=D        автопилот едет строго по курсу D градусов (0 — +x, 90 — +z), без объезда
rem   --no-shadows      без теней
rem   --bench=S         бенчмарк S секунд с автопилотом, затем отчёт и выход
rem   --shots=N         N скриншотов в build\shots (интервал --shot-every=S, по умолчанию 3 с)
rem   --snapshot-at=S   отладочный снимок (как по F12) через S секунд

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
echo   --seed=N          задаёт мир (по умолчанию — от времени)
echo   --zoom=N          камера в N раз крупнее
echo   --spawn=X,Z       старт в точке мира вместо площадки
echo   --autopilot       машина едет сама
echo   --course=D        автопилот едет строго по курсу D градусов (0 — +x, 90 — +z), без объезда
echo   --no-shadows      без теней
echo   --bench=S         бенчмарк S секунд с автопилотом, затем отчёт и выход
echo   --shots=N         N скриншотов в build\shots (интервал --shot-every=S, по умолчанию 3 с)
echo   --snapshot-at=S   отладочный снимок (как по F12) через S секунд
echo.
echo Пример: play.cmd --seed=1 --spawn=79,-18 --zoom=2
echo В игре: W/A/S/D — движение, Q/E — поворот камеры, F3 — отладка, F12 — отладочный снимок в build\debug
chcp %_oldcp% >nul
exit /b
