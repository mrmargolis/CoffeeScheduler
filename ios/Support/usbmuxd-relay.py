#!/usr/bin/env python3
"""Expose the Windows usbmuxd (Apple Devices / iTunes) to WSL as a Unix socket.

    usbmuxd-relay.py <socket path> <path to node.exe>

Apple's usbmuxd listens on the Windows side's 127.0.0.1:27015, which WSL's
default NAT networking can't reach. Each connection to the socket is handed to
a node.exe started through WSL interop, which pipes it to that port.
"""
import os
import socket
import subprocess
import sys

PIPE_JS = (
    "const s=require('net').connect(27015,'127.0.0.1');"
    "process.stdin.pipe(s);s.pipe(process.stdout);"
    "s.on('close',()=>process.exit(0));s.on('error',()=>process.exit(1));"
)


def main() -> None:
    path, node = sys.argv[1], sys.argv[2]
    if os.path.exists(path):
        os.unlink(path)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(16)
    print("ready", flush=True)
    while True:
        conn, _ = server.accept()
        subprocess.Popen([node, "-e", PIPE_JS], stdin=conn, stdout=conn, cwd="/mnt/c")
        conn.close()


if __name__ == "__main__":
    main()
