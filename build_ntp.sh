#!/bin/sh
# Cross build on Linux. Needs: nasm, gcc-mingw-w64-i686
#   sudo apt-get install -y nasm gcc-mingw-w64-i686
set -e
nasm -f win32 syncntp.asm -o syncntp.obj
# -nostartfiles + own _start entry: no C runtime -> tiny exe
i686-w64-mingw32-gcc -nostartfiles -e _start -s \
    syncntp.obj -o syncntp.exe -lws2_32 -lkernel32
echo "Built syncntp.exe"
