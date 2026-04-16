@echo off
title FFXI Chat Viewer
echo.
echo   FFXI Chat Viewer - starting server...
echo   Close this window to stop the viewer.
echo.

:: Try to find the logs folder automatically
set "LOGDIR="

:: Check common Ashita install locations
if exist "C:\Ashita4\config\addons\chatlog\logs" (
    set "LOGDIR=C:\Ashita4\config\addons\chatlog\logs"
    goto :found
)
if exist "D:\Ashita4\config\addons\chatlog\logs" (
    set "LOGDIR=D:\Ashita4\config\addons\chatlog\logs"
    goto :found
)
if exist "%USERPROFILE%\Desktop\Ashita4\config\addons\chatlog\logs" (
    set "LOGDIR=%USERPROFILE%\Desktop\Ashita4\config\addons\chatlog\logs"
    goto :found
)

:: Not found — ask the user
echo   Could not auto-detect your Ashita logs folder.
echo   Drag and drop the logs folder here, or type the path:
echo   (e.g. C:\Ashita4\config\addons\chatlog\logs)
echo.
set /p LOGDIR="   Path: "

:found
echo   Using: %LOGDIR%
echo.

:: Try python, then python3, then py
where python >nul 2>nul
if %errorlevel%==0 (
    python "%~dp0server.py" "%LOGDIR%"
    goto :done
)
where python3 >nul 2>nul
if %errorlevel%==0 (
    python3 "%~dp0server.py" "%LOGDIR%"
    goto :done
)
where py >nul 2>nul
if %errorlevel%==0 (
    py "%~dp0server.py" "%LOGDIR%"
    goto :done
)

echo.
echo   ERROR: Python is not installed or not in your PATH.
echo   Download it from https://www.python.org/downloads/
echo   Make sure to check "Add Python to PATH" during install.
echo.
pause

:done
