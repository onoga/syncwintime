; syncntp.asm - Win32 console app, x86 (NASM, Intel syntax)
;
; Port of syncntp.py: queries an NTP server (UDP/123) with a hand-built
; 48-byte packet, reads the Transmit Timestamp and sets the Windows clock.
;
; Calendar math is avoided by converting the NTP time to a Win32 FILETIME
; (100-ns ticks since 1601) and letting FileTimeToSystemTime() break it down.
;
; Build (cross, on Linux):
;   nasm -f win32 syncntp.asm -o syncntp.obj
;   i686-w64-mingw32-gcc -nostartfiles -e _start -s syncntp.obj -o syncntp.exe -lws2_32 -lkernel32
;
; NOTE: SetSystemTime requires Administrator privileges.

        global  _start

        ; --- ws2_32.dll ---
        extern  _WSAStartup@8
        extern  _gethostbyname@4
        extern  _socket@12
        extern  _setsockopt@20
        extern  _sendto@24
        extern  _recvfrom@24
        extern  _closesocket@4
        extern  _htons@4
        ; --- kernel32.dll ---
        extern  _FileTimeToSystemTime@8
        extern  _SetSystemTime@4
        extern  _GetStdHandle@4
        extern  _WriteFile@20
        extern  _ExitProcess@4

; Seconds between the FILETIME epoch (1601) and the NTP epoch (1900):
;   (1601->1970) 11644473600  -  (1900->1970) 2208988800  =  9435484800
; Split as high:low for 64-bit add (9435484800 = 2 * 2^32 + 845550208).
EPOCH_LOW   equ 845550208
EPOCH_HIGH  equ 2

; --------------------------------------------------------------------------
section .data

host            db "time.nist.gov", 0

; NTP request: byte0 = 0x1B (LI=0, VN=3, Mode=3 client), rest zero.
ntpreq          db 0x1B
                times 47 db 0

rcvtimeo        dd 5000             ; SO_RCVTIMEO, milliseconds

msg_q           db "Querying NTP time.nist.gov:123", 10
msg_q_len       equ $ - msg_q

msg_ok          db "System time updated", 10
msg_ok_len      equ $ - msg_ok

msg_setfail     db "SetSystemTime failed (run as Administrator)", 10
msg_setfail_len equ $ - msg_setfail

msg_err         db "Network error", 10
msg_err_len     equ $ - msg_err

; --------------------------------------------------------------------------
section .bss

wsadata     resb 512        ; WSADATA
buf         resb 64         ; recv buffer (>= 48)
ft          resd 2          ; FILETIME (low, high)
st          resw 8          ; SYSTEMTIME
sa          resb 16         ; sockaddr_in
hstdout     resd 1
written     resd 1
sock        resd 1

; --------------------------------------------------------------------------
section .text

%macro PRINT 2
        push    0
        push    written
        push    %2
        push    %1
        push    dword [hstdout]
        call    _WriteFile@20
%endmacro

_start:
        push    -11                 ; GetStdHandle(STD_OUTPUT_HANDLE)
        call    _GetStdHandle@4
        mov     [hstdout], eax

        push    wsadata             ; WSAStartup(0x0202, &wsadata)
        push    0x0202
        call    _WSAStartup@8

        PRINT   msg_q, msg_q_len

        push    host                ; gethostbyname("time.nist.gov")
        call    _gethostbyname@4
        test    eax, eax
        jz      neterr
        mov     eax, [eax + 12]     ; h_addr_list
        mov     eax, [eax]          ; h_addr_list[0]
        mov     eax, [eax]          ; in_addr
        mov     [sa + 4], eax       ; sin_addr

        mov     word [sa], 2        ; sin_family = AF_INET

        push    123                 ; sin_port = htons(123)
        call    _htons@4
        mov     [sa + 2], ax

        push    0                   ; socket(AF_INET, SOCK_DGRAM, 0)
        push    2
        push    2
        call    _socket@12
        cmp     eax, -1
        je      neterr
        mov     [sock], eax

        ; setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &rcvtimeo, 4)
        push    4
        push    rcvtimeo
        push    0x1006              ; SO_RCVTIMEO
        push    0xFFFF              ; SOL_SOCKET
        push    dword [sock]
        call    _setsockopt@20

        ; sendto(sock, ntpreq, 48, 0, &sa, 16)
        push    16
        push    sa
        push    0
        push    48
        push    ntpreq
        push    dword [sock]
        call    _sendto@24
        cmp     eax, -1
        je      neterr

        ; recvfrom(sock, buf, 48, 0, NULL, NULL)
        push    0
        push    0
        push    0
        push    48
        push    buf
        push    dword [sock]
        call    _recvfrom@24
        cmp     eax, 48
        jl      neterr

        push    dword [sock]
        call    _closesocket@4

        ; --- NTP Transmit Timestamp -> FILETIME ---
        ; seconds part (buf+40, network byte order)
        mov     eax, [buf + 40]
        bswap   eax                 ; -> NTP seconds since 1900
        xor     edx, edx
        add     eax, EPOCH_LOW      ; + 9435484800 (64-bit) -> seconds since 1601
        adc     edx, EPOCH_HIGH
        ; multiply 64-bit (edx:eax) by 10,000,000 (100-ns ticks per second)
        mov     ebx, eax            ; save low
        mov     esi, edx            ; save high
        mov     ecx, 10000000
        mov     eax, ebx
        mul     ecx                 ; edx:eax = low * 1e7
        mov     edi, eax            ; FILETIME low
        mov     ebp, edx            ; carry into high
        mov     eax, esi
        mul     ecx                 ; eax = high * 1e7 (mod 2^32)
        add     eax, ebp            ; FILETIME high
        mov     [ft + 0], edi
        mov     [ft + 4], eax

        ; fractional part (buf+44): add frac * 1e7 / 2^32 in 100-ns ticks
        mov     eax, [buf + 44]
        bswap   eax
        mov     ecx, 10000000
        mul     ecx                 ; edx = floor(frac * 1e7 / 2^32)
        add     [ft + 0], edx
        adc     dword [ft + 4], 0

        ; FileTimeToSystemTime(&ft, &st)  (UTC -> UTC fields)
        push    st
        push    ft
        call    _FileTimeToSystemTime@8
        test    eax, eax
        jz      neterr

        ; SetSystemTime(&st)
        push    st
        call    _SetSystemTime@4
        test    eax, eax
        jz      setfail

        PRINT   msg_ok, msg_ok_len
        push    0
        call    _ExitProcess@4

setfail:
        PRINT   msg_setfail, msg_setfail_len
        push    1
        call    _ExitProcess@4

neterr:
        PRINT   msg_err, msg_err_len
        push    1
        call    _ExitProcess@4
