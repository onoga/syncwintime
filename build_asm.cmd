@echo off
REM Native build on Windows. Needs NASM and MinGW (i686/gcc) on PATH.
nasm -f win32 syncwintime.asm -o syncwintime.obj || exit /b 1
gcc -m32 -nostartfiles -e _start -s syncwintime.obj -o syncwintime.exe -lws2_32 -lkernel32 || exit /b 1
echo Built syncwintime.exe
