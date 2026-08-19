@echo off
title SOCKS tunnel (127.0.0.1:5555)
rem Login and host are NOT stored here - they live in tunnel.local.cmd,
rem which is listed in .gitignore and never gets committed.
rem First run: copy tunnel.example.cmd -> tunnel.local.cmd and fill it in.

if not exist "%~dp0tunnel.local.cmd" (
    echo [X] Not found: %~dp0tunnel.local.cmd
    echo     Copy tunnel.example.cmd to tunnel.local.cmd and put your SSH login there.
    pause
    exit /b 1
)

call "%~dp0tunnel.local.cmd"

if "%SSH_TARGET%"=="" (
    echo [X] SSH_TARGET is not set in tunnel.local.cmd
    pause
    exit /b 1
)
if "%SOCKS_PORT%"=="" set SOCKS_PORT=5555

:loop
ssh %SSH_TARGET% -D %SOCKS_PORT% -N -C -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes
timeout /t 5 >nul
goto loop
