@echo off
rem Copy this file to tunnel.local.cmd and put your own SSH login there.
rem tunnel.local.cmd is in .gitignore, so it never reaches the repository.

set SSH_TARGET=user@proxy.example.com
set SOCKS_PORT=5555
