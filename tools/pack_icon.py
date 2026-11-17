"""Package PNG icon representations in Apple's ICNS container without IconServices."""
from pathlib import Path
import struct

root = Path(__file__).resolve().parents[1]
representations = [(b"icp4", "16x16"), (b"icp5", "32x32"), (b"icp6", "32x32@2x"),
                   (b"ic07", "128x128"), (b"ic08", "256x256"), (b"ic09", "512x512"),
                   (b"ic10", "512x512@2x"), (b"ic11", "16x16@2x"),
                   (b"ic12", "32x32@2x"), (b"ic13", "128x128@2x"), (b"ic14", "256x256@2x")]
chunks = []
for tag, name in representations:
    png = (root / "build" / "AirPause.iconset" / f"icon_{name}.png").read_bytes()
    chunks.append(tag + struct.pack(">I", len(png) + 8) + png)
data = b"".join(chunks)
(root / "build" / "气间 AirPause.app" / "Contents" / "Resources" / "AirPause.icns").write_bytes(b"icns" + struct.pack(">I", len(data) + 8) + data)
