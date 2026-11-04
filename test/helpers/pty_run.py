#!/usr/bin/env python3
"""Run a command in a pseudo-terminal and drive it, for tests that need a
real terminal (readline, prompts, pastes).

Usage: pty_run.py STEP... -- COMMAND [ARG...]

Steps, in order:
  send:TEXT     write TEXT (backslash escapes: \\r \\n \\t \\x1b ...)
  expect:TEXT   wait until TEXT has appeared in the output as it would
                show on screen, after what the last expect matched: escape
                sequences, readline's \\001 and \\002 and carriage returns
                are left out (10s at most)
  sleep:SECS    wait

PTY_SIZE=COLSxROWS in the environment sets the terminal size (default:
whatever the pseudo-terminal starts with, often 0x0).

The output (with escape sequences) goes to stdout. The exit status is the
command's, or 124 when an expect step times out.
"""
import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time


SCREEN_NOISE = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]|[\x01\x02\r]")


def screen(data):
    return SCREEN_NOISE.sub(b"", data)


def unescape(text):
    return text.encode().decode("unicode_escape").encode("latin-1")


def main():
    args = sys.argv[1:]
    split = args.index("--")
    steps, command = args[:split], args[split + 1:]
    pid, fd = pty.fork()
    if pid == 0:
        size = os.environ.get("PTY_SIZE", "")
        if size:
            cols, rows = (int(n) for n in size.split("x"))
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.execvp(command[0], command)
    out = b""

    def read_for(seconds):
        nonlocal out
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    return False
                if not chunk:
                    return False
                out += chunk
        return True

    status = 0
    matched_to = 0  # in the screen text: where the last expect's match ended
    for step in steps:
        kind, _, value = step.partition(":")
        if kind == "send":
            os.write(fd, unescape(value))
        elif kind == "sleep":
            read_for(float(value))
        elif kind == "expect":
            want = unescape(value)
            end = time.time() + 10
            while screen(out).find(want, matched_to) < 0 and time.time() < end:
                if not read_for(0.1):
                    break
            found = screen(out).find(want, matched_to)
            if found < 0:
                status = 124
                break
            matched_to = found + len(want)
    read_for(1.0)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass
    _, code = os.waitpid(pid, 0)
    sys.stdout.write(out.decode(errors="replace"))
    if status == 0 and os.WIFEXITED(code):
        status = os.WEXITSTATUS(code)
    sys.exit(status)


main()
