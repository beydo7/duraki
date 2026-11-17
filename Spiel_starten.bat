@echo off
rem ============================================================
rem  Duraki direkt starten, ohne den Godot-Editor zu oeffnen.
rem
rem  Godot wird in dieser Reihenfolge gesucht:
rem   1. Umgebungsvariable GODOT (voller Pfad zur Godot-exe)
rem   2. Ordner "Godot" neben dem Projektordner  (..\Godot\)
rem   3. Projektordner selbst
rem   4. godot.exe im PATH
rem
rem  Optional: eine Szene direkt starten, z. B.
rem    Spiel_starten.bat res://scenes/match/match.tscn
rem ============================================================
setlocal
cd /d "%~dp0"

set "GODOT_EXE=%GODOT%"
if not defined GODOT_EXE for %%F in ("%~dp0..\Godot\Godot_v4*_win64.exe") do set "GODOT_EXE=%%~fF"
if not defined GODOT_EXE for %%F in ("%~dp0Godot_v4*_win64.exe") do set "GODOT_EXE=%%~fF"
if not defined GODOT_EXE for %%G in (godot.exe) do if not "%%~$PATH:G"=="" set "GODOT_EXE=%%~$PATH:G"

if not defined GODOT_EXE goto :not_found
if not exist "%GODOT_EXE%" goto :not_found

rem Vor jedem Start importieren, damit neue/geaenderte Skripte und Klassen
rem (class_name) erkannt werden. Dauert nur ein paar Sekunden.
echo Projekt wird aktualisiert, bitte kurz warten ...
"%GODOT_EXE%" --headless --path "%CD%" --import >nul 2>&1

start "" "%GODOT_EXE%" --path "%CD%" %*
exit /b 0

:not_found
echo.
echo  Godot 4.7 wurde nicht gefunden.
echo.
echo  Loesung: Godot_v4.7.2-stable_win64.exe in einen Ordner "Godot"
echo  neben den Projektordner legen, z. B.
echo     D:\Games\Duraki\Godot\Godot_v4.7.2-stable_win64.exe
echo     D:\Games\Duraki\duraki\Spiel_starten.bat
echo.
echo  Oder die Umgebungsvariable GODOT auf den Pfad der exe setzen.
echo.
pause
exit /b 1
