#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# syncntp.py - synchronise the Windows system clock over NTP (UDP/123),
# implemented from scratch: no ntplib, just raw sockets + struct.
#
# Unlike syncwintime.py (Daytime/RFC 867, second-accurate text), this speaks
# real NTP: it builds the 48-byte packet by hand, reads the server timestamps
# and corrects for network round-trip delay (the classic t1..t4 method).
#
# Runs on Python 2.7 and 3.x (handy for ancient boxes like Windows 2000).

from __future__ import print_function

import socket
import struct
import sys
import time

# NTP epoch is 1900-01-01, Unix epoch is 1970-01-01.
NTP_DELTA = 2208988800  # seconds between them


def ntp_to_unix(seconds, fraction):
    """64-bit NTP timestamp (32.32 fixed point) -> Unix seconds (float)."""
    return seconds + fraction / 2.0**32 - NTP_DELTA


def query_ntp(host, port=123, timeout=5):
    """Return (server_time, offset) in Unix seconds.

    server_time - best estimate of true UTC at the moment of return.
    offset      - how far the local clock is off (true = local + offset).
    """
    # First byte: LI=0 (no warning), VN=3 (version), Mode=3 (client) -> 0x1B.
    # The remaining 47 bytes are left zero.
    request = b'\x1b' + 47 * b'\x00'

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    try:
        t1 = time.time()                 # client transmit time
        sock.sendto(request, (host, port))
        data, _ = sock.recvfrom(48)
        t4 = time.time()                 # client receive time
    finally:
        sock.close()

    if len(data) < 48:
        raise ValueError("short NTP reply: %d bytes" % len(data))

    # 12 big-endian 32-bit words. Words 8/9 = Receive Timestamp (t2),
    # words 10/11 = Transmit Timestamp (t3).
    words = struct.unpack('!12I', data[:48])
    t2 = ntp_to_unix(words[8], words[9])
    t3 = ntp_to_unix(words[10], words[11])

    # Standard NTP clock-offset estimate (cancels symmetric path delay).
    offset = ((t2 - t1) + (t3 - t4)) / 2.0
    return t4 + offset, offset


def set_system_time(unix_time):
    """Set the Windows system clock (UTC) from a Unix timestamp."""
    import ctypes

    class SYSTEMTIME(ctypes.Structure):
        _fields_ = [
            ('wYear', ctypes.c_uint16),
            ('wMonth', ctypes.c_uint16),
            ('wDayOfWeek', ctypes.c_uint16),
            ('wDay', ctypes.c_uint16),
            ('wHour', ctypes.c_uint16),
            ('wMinute', ctypes.c_uint16),
            ('wSecond', ctypes.c_uint16),
            ('wMilliseconds', ctypes.c_uint16)]

    g = time.gmtime(unix_time)
    millis = int((unix_time - int(unix_time)) * 1000)
    st = SYSTEMTIME(g.tm_year, g.tm_mon, 0, g.tm_mday,
                    g.tm_hour, g.tm_min, g.tm_sec, millis)
    # SetSystemTime expects UTC and needs Administrator privileges.
    return ctypes.windll.kernel32.SetSystemTime(ctypes.byref(st)) == 1


def main():
    host = sys.argv[1] if len(sys.argv) > 1 else 'time.nist.gov'
    print("Querying NTP %s:123" % host)
    try:
        true_time, offset = query_ntp(host)
    except Exception as e:
        print("NTP query failed:", e)
        sys.exit(1)

    print("Server UTC : %s.%03d" % (
        time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime(true_time)),
        int((true_time - int(true_time)) * 1000)))
    print("Local clock is off by %+.3f s" % offset)

    if not sys.platform.startswith('win'):
        print("Not on Windows - clock not changed.")
        sys.exit(0)

    if set_system_time(true_time):
        print("System time updated")
        sys.exit(0)
    else:
        print("SetSystemTime failed (run as Administrator)")
        sys.exit(1)


if __name__ == '__main__':
    main()
