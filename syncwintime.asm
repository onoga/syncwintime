; syncwintime.asm — Win32 console app, x86 (NASM, Intel syntax)
;
; Port of syncwintime.py: connects to time.nist.gov:13 (Daytime / RFC 867),
; parses the UTC time and sets the Windows system clock via SetSystemTime.
;
; Build (cross, on Linux):
;   nasm -f win32 syncwintime.asm -o syncwintime.obj
;   i686-w64-mingw32-gcc -nostartfiles -e _start -s syncwintime.obj -o syncwintime.exe -lws2_32 -lkernel32
;
; Build (native, on Windows with NASM + MinGW):
;   build_asm.cmd
;
; NOTE: SetSystemTime requires Administrator privileges. Run the .exe elevated.

        global  _start

        ; --- ws2_32.dll ---
        extern  _WSAStartup@8
        extern  _gethostbyname@4
        extern  _socket@12
        extern  _connect@12
        extern  _recv@16
        extern  _closesocket@4
        extern  _htons@4
        ; --- kernel32.dll ---
        extern  _SetSystemTime@4
        extern  _GetStdHandle@4
        extern  _WriteFile@20
        extern  _ExitProcess@4

; --------------------------------------------------------------------------
section .data

host            db "time.nist.gov", 0

msg_conn        db "Connecting time.nist.gov:13", 10
msg_conn_len    equ $ - msg_conn

msg_recv        db "Received time: "
msg_recv_len    equ $ - msg_recv

msg_ok          db "System time updated", 10
msg_ok_len      equ $ - msg_ok

msg_setfail     db "SetSystemTime failed (run as Administrator)", 10
msg_setfail_len equ $ - msg_setfail

msg_err         db "Network error", 10
msg_err_len     equ $ - msg_err

nl              db 10

; --------------------------------------------------------------------------
section .bss

wsadata     resb 512        ; WSADATA
buf         resb 64         ; recv buffer
st          resw 8          ; SYSTEMTIME (8 x WORD)
sa          resb 16         ; sockaddr_in
hstdout     resd 1
written     resd 1
sock        resd 1

; --------------------------------------------------------------------------
section .text

; PRINT buf, len  ->  WriteFile(hstdout, buf, len, &written, NULL)
%macro PRINT 2
        push    0
        push    written
        push    %2
        push    %1
        push    dword [hstdout]
        call    _WriteFile@20
%endmacro

; P2 off  ->  eax = (buf[off]-'0')*10 + (buf[off+1]-'0')
%macro P2 1
        movzx   eax, byte [buf + %1]
        sub     eax, '0'
        imul    eax, eax, 10
        movzx   edx, byte [buf + %1 + 1]
        sub     edx, '0'
        add     eax, edx
%endmacro

_start:
        ; hstdout = GetStdHandle(STD_OUTPUT_HANDLE = -11)
        push    -11
        call    _GetStdHandle@4
        mov     [hstdout], eax

        ; WSAStartup(MAKEWORD(2,2), &wsadata)
        push    wsadata
        push    0x0202
        call    _WSAStartup@8

        PRINT   msg_conn, msg_conn_len

        ; he = gethostbyname("time.nist.gov")
        push    host
        call    _gethostbyname@4
        test    eax, eax
        jz      neterr
        mov     eax, [eax + 12]     ; he->h_addr_list
        mov     eax, [eax]          ; h_addr_list[0]
        mov     eax, [eax]          ; in_addr (4 bytes)
        mov     [sa + 4], eax       ; sin_addr

        mov     word [sa], 2        ; sin_family = AF_INET

        ; sin_port = htons(13)
        push    13
        call    _htons@4
        mov     [sa + 2], ax

        ; sock = socket(AF_INET, SOCK_STREAM, 0)
        push    0
        push    1
        push    2
        call    _socket@12
        cmp     eax, -1             ; INVALID_SOCKET
        je      neterr
        mov     [sock], eax

        ; connect(sock, &sa, 16)
        push    16
        push    sa
        push    dword [sock]
        call    _connect@12
        test    eax, eax            ; 0 = OK
        jnz     neterr

        ; recv(sock, buf, 24, 0)
        push    0
        push    24
        push    buf
        push    dword [sock]
        call    _recv@16
        cmp     eax, 24             ; need full "..YY-MM-DD HH:MM:SS"
        jl      neterr

        push    dword [sock]
        call    _closesocket@4

        ; echo the parsed timestamp: buf[7 .. 7+17]
        PRINT   msg_recv, msg_recv_len
        PRINT   buf + 7, 17
        PRINT   nl, 1

        ; fill SYSTEMTIME from the fixed offsets of the NIST daytime line
        P2      7                   ; YY
        add     eax, 2000
        mov     [st + 0], ax        ; wYear
        P2      10                  ; MM
        mov     [st + 2], ax        ; wMonth
        mov     word [st + 4], 0    ; wDayOfWeek (ignored)
        P2      13                  ; DD
        mov     [st + 6], ax        ; wDay
        P2      16                  ; HH
        mov     [st + 8], ax        ; wHour
        P2      19                  ; MM
        mov     [st + 10], ax       ; wMinute
        P2      22                  ; SS
        mov     [st + 12], ax       ; wSecond
        mov     word [st + 14], 0   ; wMilliseconds

        ; SetSystemTime(&st)   (time is UTC, as required)
        push    st
        call    _SetSystemTime@4
        test    eax, eax
        jz      setfail

        PRINT   msg_ok, msg_ok_len
        push    0                   ; ExitProcess(0)
        call    _ExitProcess@4

setfail:
        PRINT   msg_setfail, msg_setfail_len
        push    1                   ; ExitProcess(1)
        call    _ExitProcess@4

neterr:
        PRINT   msg_err, msg_err_len
        push    1                   ; ExitProcess(1)
        call    _ExitProcess@4
