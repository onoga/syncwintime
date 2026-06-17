@echo off
REM Native build on Windows. Needs NASM and MinGW (i686/gcc) on PATH.
nasm -f win32 syncntp.asm -o syncntp.obj || exit /b 1
gcc -m32 -nostartfiles -e _start -s syncntp.obj -o syncntp.exe -lws2_32 -lkernel32 || exit /b 1
echo Built syncntp.exe
