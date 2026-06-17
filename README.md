# syncwintime

Tiny tools to set the **Windows system clock** from an internet time server.

What started as a small Python script grew into a set of implementations — from
a one-line Python port to hand-written x86 assembly that compiles to a **3.5 KB**
native `.exe` with zero runtime dependencies. Handy for old or minimal Windows
boxes (works all the way down to Windows 2000).

## Variants

| File | Protocol | Language | Output | Accuracy |
|------|----------|----------|--------|----------|
| `syncwintime.py` | Daytime / RFC 867 (TCP 13) | Python (ctypes) | — | second |
| `syncntp.py` | NTP (UDP 123) | Python (no deps) | — | sub-second, round-trip corrected |
| `syncwintime.asm` | Daytime / RFC 867 (TCP 13) | x86 NASM | `syncwintime.exe` (~3.5 KB) | second |
| `syncntp.asm` | NTP (UDP 123) | x86 NASM | `syncntp.exe` (~3.5 KB) | sub-second |

Prebuilt `syncwintime.exe` and `syncntp.exe` are checked into the repo.

## Usage

Run on Windows **as Administrator** — setting the system clock requires it.

```
syncntp.exe              REM NTP, default server time.nist.gov
syncwintime.exe          REM Daytime/13
```

The Python versions take an optional server argument and also run on
non-Windows for testing (where they print the offset instead of changing the
clock):

```
python syncntp.py pool.ntp.org
```

The `.exe` builds are 32-bit, so a single binary runs on **32-bit, 64-bit and
ARM64 Windows** (via WOW64 / x86 emulation). They link only against
`kernel32.dll` and `ws2_32.dll`.

## Building the assembly versions

Requires [NASM](https://www.nasm.us/) and a 32-bit MinGW toolchain.

**On Linux (cross-compile):**
```sh
sudo apt-get install -y nasm gcc-mingw-w64-i686
sh build_asm.sh     # -> syncwintime.exe
sh build_ntp.sh     # -> syncntp.exe
```

**On Windows (NASM + MinGW on PATH):**
```bat
build_asm.cmd
build_ntp.cmd
```

The build uses a custom `_start` entry point with `-nostartfiles`, so no C
runtime is linked in — that is what keeps the binaries at ~3.5 KB.

## How it works

1. Resolve the server (`gethostbyname`) and open a socket via Winsock.
2. **Daytime:** read the ASCII line and parse the fixed `YY-MM-DD HH:MM:SS`
   offsets. **NTP:** send a 48-byte request and read the Transmit Timestamp.
3. Fill a `SYSTEMTIME` (UTC) and call `SetSystemTime`.

The NTP assembly version sidesteps calendar math by converting the timestamp to
a Win32 `FILETIME` (100-ns ticks since 1601) and letting `FileTimeToSystemTime`
break it down into date fields.

## Notes / caveats

- **Administrator required** — `SetSystemTime` fails otherwise.
- Time is treated as **UTC**; the local time zone offset is applied by Windows.
- Needs outbound access to the time server (TCP 13 for Daytime, UDP 123 for
  NTP); both ports are sometimes blocked by firewalls.
- The Daytime variants are second-accurate. The NTP assembly reads the server
  timestamp directly; only `syncntp.py` additionally corrects for network
  round-trip delay (the `t1..t4` offset estimate).

## License

MIT — see [LICENSE](LICENSE).
