import ctypes
import re
import socket
import sys


class SYSTEMTIME(ctypes.Structure):
    _fields_ = [
        ('wYear', ctypes.c_int16),
        ('wMonth', ctypes.c_int16),
        ('wDayOfWeek', ctypes.c_int16),
        ('wDay', ctypes.c_int16),
        ('wHour', ctypes.c_int16),
        ('wMinute', ctypes.c_int16),
        ('wSecond', ctypes.c_int16),
        ('wMilliseconds', ctypes.c_int16)]


def sync_win_time(host, port):
    print("Connecting %s:%s" % (host, port))
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((host, port))
    text = sock.recv(24)[7:].decode('ascii')
    m = re.match(r'(\d\d)-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)', text)
    if m:
        print("Received time:", text)
        year, month, day, hour, minute, sec = map(int, m.groups())
        time = SYSTEMTIME(2000 + year, month, 0, day, hour, minute, sec, 0)
        rc = ctypes.windll.kernel32.SetSystemTime(ctypes.byref(time))
        if rc == 1:
            print("System time updated")
            sys.exit(0)
        else:
            print("win32api.SetSystemTime returned", rc)
            sys.exit(1)
    else:
        print("Can't parse time:", text)
        sys.exit(1)


if __name__ == '__main__':
    sync_win_time('time.nist.gov', 13)
