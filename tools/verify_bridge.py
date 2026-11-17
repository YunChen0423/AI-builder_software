"""Integration checks against App --bridge-smoke (loopback only)."""
import json
import socket
import time

def connect():
    sock = socket.create_connection(("127.0.0.1", 18457), timeout=2)
    return sock, sock.makefile("rb")

def until(reader, predicate):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        frame = json.loads(reader.readline())
        assert frame["simulated"] is True and frame["ttl_ms"] == 750
        assert frame["air"] == [1, 0.6, 1]
        if predicate(frame):
            return frame
    raise AssertionError("Expected frame not received")

sock, reader = connect()
until(reader, lambda f: f["mode"] == "working")
line = b'{"type":"contact","version":1,"sequence":10,"pressed":true}\n'
sock.sendall(b"bad json\n" + line[:18])
time.sleep(0.1)
sock.sendall(line[18:])
until(reader, lambda f: f.get("contact") is True)
sock.sendall(b'{"type":"contact","version":1,"sequence":9,"pressed":false}\n')
time.sleep(0.2)
assert json.loads(reader.readline()).get("contact") is True
sock.sendall(b'{"type":"contact","version":1,"sequence":11,"pressed":false}\n')
until(reader, lambda f: f.get("contact") is False)
until(reader, lambda f: "contact" not in f)
reader.close()
sock.close()
time.sleep(0.2)
sock, reader = connect()
sock.sendall(b'{"type":"contact","version":1,"sequence":1,"pressed":true}\n')
until(reader, lambda f: f.get("contact") is True)
sock.sendall(b"x" * 3000)
while reader.readline():
    pass
reader.close()
sock.close()
print("PASS: loopback, target schema, fragmented JSON, malformed JSON, sequence replay, freshness expiry, reconnect, oversized input")
