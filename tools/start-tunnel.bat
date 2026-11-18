@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title SOCKS tunnel (127.0.0.1:5555)

if not exist "%~dp0tunnel.active.cmd" (
    echo [X] No tunnel.active.cmd. Open 5S Launcher and add a server.
    echo [X] No tunnel.active.cmd. Open 5S Launcher and add a server.>"%~dp0tunnel.log"
    if not defined NO_PAUSE pause
    exit /b 1
)

call "%~dp0tunnel.active.cmd"

if "%SSH_TARGET%"=="" (
    echo [X] SSH_TARGET is empty. Choose a server in 5S Launcher.
    echo [X] SSH_TARGET is empty. Choose a server in 5S Launcher.>"%~dp0tunnel.log"
    if not defined NO_PAUSE pause
    exit /b 1
)
if "%SOCKS_PORT%"=="" set SOCKS_PORT=5555
if "%SSH_BIND%"=="" (
    set "SSH_BIND_ARG="
) else (
    set "SSH_BIND_ARG=-b %SSH_BIND%"
)

:loop
if "%SSH_IDENTITY%"=="" (
    ssh %SSH_BIND_ARG% "%SSH_TARGET%" -D 127.0.0.1:%SOCKS_PORT% -N -C -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes > "%~dp0tunnel.log" 2>&1
) else (
    ssh %SSH_BIND_ARG% -i "%SSH_IDENTITY%" -o IdentitiesOnly=yes "%SSH_TARGET%" -D 127.0.0.1:%SOCKS_PORT% -N -C -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes > "%~dp0tunnel.log" 2>&1
)
if exist "%~dp0tunnel.userstop" (
    del /f /q "%~dp0tunnel.userstop"
    exit /b 0
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0stop-claude.ps1"
ping -n 6 127.0.0.1 >nul
goto loop
