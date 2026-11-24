@echo off
rem ============================================================
rem  3D-Modelle aus Blender nach Godot exportieren.
rem
rem  Oeffnet jede .blend in art\blender\ (Raum, Tisch, Requisiten,
rem  Gegner) und exportiert sie als .glb nach assets\models\.
rem  Die .blend-Dateien werden dabei NICHT veraendert.
rem
rem  Nur ein Modell:   Modelle_exportieren.bat table
rem                    Modelle_exportieren.bat wolf
rem  Achtung: "--rebuild" baut aus dem Skript neu und
rem  UEBERSCHREIBT die .blend. Nur nutzen, wenn ihr das wollt.
rem
rem  Blender wird in dieser Reihenfolge gesucht:
rem   1. Umgebungsvariable BLENDER (voller Pfad zur blender.exe)
rem   2. C:\Program Files\Blender Foundation\Blender *\blender.exe
rem   3. blender.exe im PATH
rem ============================================================
setlocal
cd /d "%~dp0"

set "BLENDER_EXE=%BLENDER%"
if not defined BLENDER_EXE for /d %%D in ("%ProgramFiles%\Blender Foundation\Blender *") do if exist "%%~fD\blender.exe" set "BLENDER_EXE=%%~fD\blender.exe"
if not defined BLENDER_EXE for %%G in (blender.exe) do if not "%%~$PATH:G"=="" set "BLENDER_EXE=%%~$PATH:G"

if not defined BLENDER_EXE goto :not_found
if not exist "%BLENDER_EXE%" goto :not_found

echo Blender: %BLENDER_EXE%
echo Modelle werden exportiert, das dauert einen Moment ...
echo.
"%BLENDER_EXE%" -b -P "art\blender\build_models.py" -- %*
echo.
echo Fertig. Beim naechsten Start (Spiel_starten.bat) uebernimmt Godot die neuen Modelle.
pause
exit /b 0

:not_found
echo.
echo  Blender wurde nicht gefunden.
echo  Blender installieren (https://www.blender.org/download/)
echo  oder die Umgebungsvariable BLENDER auf den Pfad der blender.exe setzen.
echo.
pause
exit /b 1
