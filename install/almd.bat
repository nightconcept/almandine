@echo off
rem Almandine CLI wrapper script for Windows
rem Finds a suitable Lua interpreter and runs src/main.lua with all arguments.

setlocal enabledelayedexpansion
set LUA_BIN=

for %%L in (lua.exe lua5.4.exe lua5.3.exe lua5.2.exe lua5.1.exe luajit.exe) do (
  where /Q %%L
  if !errorlevel! == 0 (
    set LUA_BIN=%%L
    goto :found
  )
)

echo Error: No suitable Lua interpreter found (lua, lua5.4, lua5.3, lua5.2, lua5.1, or luajit required). 1>&2
exit /b 1

:found
rem Get the directory of this script for portability
set SCRIPT_DIR=%~dp0

rem Remove trailing backslash if present
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

rem Set LUA_PATH so Lua can find src/lib modules regardless of CWD
set "LUA_PATH=%SCRIPT_DIR%\src\?.lua;%SCRIPT_DIR%\src\lib\?.lua;;"

"%LUA_BIN%" "%SCRIPT_DIR%\src\main.lua" %*
exit /b %ERRORLEVEL%
