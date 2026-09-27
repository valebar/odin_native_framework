@echo off
rem Builds app/ for Windows (Win32) and runs it. The console stays attached for app output.
cd /d "%~dp0.."
if not exist build\windows mkdir build\windows
odin build app -debug -resource:windows\app.rc -out:build\windows\example.exe || exit /b 1
rem Relative paths in bitmap_from_file resolve against the assets directory next to the exe.
xcopy /e /i /y /q app\assets build\windows\assets > nul
build\windows\example.exe
