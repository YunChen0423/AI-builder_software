"""Opt-in local test adapter. Does not connect to physical hardware."""
import argparse
import json
import socket
import time

parser = argparse.ArgumentParser(description="AirPause 本机接触模拟器；先在 App 中开启接口")
parser.add_argument("--seconds", type=float, default=75)
parser.add_argument("--released", action="store_true")
args = parser.parse_args()
with socket.create_connection(("127.0.0.1", 18457), timeout=3) as sock:
    sock.settimeout(0.1)
    until, sequence, buffer = time.monotonic() + args.seconds, 0, b""
    last_mode = None
    while time.monotonic() < until:
        sequence += 1
        sock.sendall((json.dumps({"version": 1, "type": "contact", "pressed": not args.released, "sequence": sequence}) + "\n").encode())
        try:
            data = sock.recv(8192)
            if not data:
                break
            buffer += data
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                frame = json.loads(line)
                if frame["mode"] != last_mode:
                    print("mode:", frame["mode"], "air:", frame["air"], "simulated:", frame["simulated"], flush=True)
                    last_mode = frame["mode"]
        except socket.timeout:
            pass
        time.sleep(0.25)
