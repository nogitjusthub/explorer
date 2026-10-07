@echo off
rem Открыть проект в редакторе Godot. Работает из любой папки.
start "" "%~dp0tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." -e %*
