@echo off
title FFXI Chat Viewer
setlocal enabledelayedexpansion

set "CFG=%~dp0chatviewer.cfg"
set "LOGDIR="

:: ---------------------------------------------------------------------------
:: 1. Check if we already have a saved path
:: ---------------------------------------------------------------------------
if exist "%CFG%" (
    set /p LOGDIR=<"%CFG%"
    if exist "!LOGDIR!" (
        echo   Using saved path: !LOGDIR!
        goto :launch
    ) else (
        echo   Saved path no longer exists: !LOGDIR!
        del "%CFG%" >nul 2>nul
        set "LOGDIR="
    )
)

:: ---------------------------------------------------------------------------
:: 2. Try to auto-detect common Ashita install locations
:: ---------------------------------------------------------------------------
for %%D in (
    "C:\Ashita4\config\addons\chatlog\logs"
    "D:\Ashita4\config\addons\chatlog\logs"
    "C:\Games\Ashita4\config\addons\chatlog\logs"
    "D:\Games\Ashita4\config\addons\chatlog\logs"
    "%USERPROFILE%\Desktop\Ashita4\config\addons\chatlog\logs"
    "%APPDATA%\HorizonXI-Launcher\HorizonXI\Game\config\addons\chatlog\logs"
) do (
    if exist %%D (
        set "LOGDIR=%%~D"
        echo   Auto-detected: !LOGDIR!
        goto :save
    )
)

:: ---------------------------------------------------------------------------
:: 3. Not found — ask the user (one time only)
:: ---------------------------------------------------------------------------
echo.
echo   Could not auto-detect your Ashita chatlog logs folder.
echo   Please enter the full path to the logs folder.
echo   Example: C:\HorizonXI\Game\config\addons\chatlog\logs
echo.
set /p LOGDIR="   Path: "

:: Strip surrounding quotes if the user pasted them
set "LOGDIR=!LOGDIR:"=!"

if not exist "!LOGDIR!" (
    echo.
    echo   ERROR: That folder does not exist.
    echo   Make sure the chatlog addon has been loaded at least once.
    pause
    exit /b 1
)

:: ---------------------------------------------------------------------------
:: 4. Save the path so we never ask again
:: ---------------------------------------------------------------------------
:save
echo !LOGDIR!>"%CFG%"
echo   Path saved to chatviewer.cfg (delete that file to reset)
echo.

:: ---------------------------------------------------------------------------
:: 5. Launch the server
:: ---------------------------------------------------------------------------
:launch
echo.
echo   Starting server... (close this window to stop)
echo.

:: Try python, python3, py in order
where python >nul 2>nul
if %errorlevel%==0 (
    python "%~dp0server.py" "!LOGDIR!"
    goto :done
)
where python3 >nul 2>nul
if %errorlevel%==0 (
    python3 "%~dp0server.py" "!LOGDIR!"
    goto :done
)
where py >nul 2>nul
if %errorlevel%==0 (
    py "%~dp0server.py" "!LOGDIR!"
    goto :done
)

echo.
echo   ERROR: Python is not installed or not in your PATH.
echo   Download it from https://www.python.org/downloads/
echo   Make sure to check "Add Python to PATH" during install.
echo.
pause

:done
