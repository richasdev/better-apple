#!/usr/bin/env python3
"""Package the supplied original logo into a macOS icon; no artwork is changed."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="betterapple-icon-") as temporary:
    iconset = Path(temporary) / "BetterApple.iconset"
    iconset.mkdir()
    source = root / "Resources/Logo/logo-dark.png"
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            target = iconset / f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            subprocess.run(["/usr/bin/sips", "-z", str(size * scale), str(size * scale), str(source), "--out", str(target)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(root / "Resources/BetterApple.icns")], check=True)
print("Packaged BetterApple.icns from the supplied logo.")
