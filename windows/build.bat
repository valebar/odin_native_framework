@echo off
rem Builds app/ for Windows (Win32) and runs it. The console stays attached for app output.
cd /d "%~dp0.."
if not exist build\windows mkdir build\windows
odin build app -debug -resource:windows\app.rc -out:build\windows\example.exe || exit /b 1
build\windows\example.exe
