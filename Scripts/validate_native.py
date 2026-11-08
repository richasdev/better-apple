#!/usr/bin/env python3
"""Compile real native integration harnesses without Xcode signing or third-party dependencies."""
import argparse
import platform
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--only", choices=["all", "services", "productivity", "dock", "widgets", "dock-motion", "widget-motion", "notch-shape"], default="all")
selection = parser.parse_args().only
architecture = platform.machine()
if architecture not in {"arm64", "x86_64"}:
    raise SystemExit("Run this harness on an arm64 or x86_64 Mac.")

def run(arguments):
    completed = subprocess.run([str(item) for item in arguments], cwd=root, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if completed.stdout:
        print(completed.stdout.rstrip(), flush=True)
    if completed.returncode:
        raise SystemExit(completed.returncode)

with tempfile.TemporaryDirectory(prefix="betterapple-native-check-") as temporary:
    directory = Path(temporary)
    compiler = ["xcrun", "swiftc", "-swift-version", "5", "-target", f"{architecture}-apple-macosx14.0"]
    run(compiler + ["-emit-library", "-emit-module", "-module-name", "BetterAppleCore"] +
        sorted((root / "Sources/BetterAppleCore").glob("*.swift")) +
        ["-emit-module-path", directory / "BetterAppleCore.swiftmodule", "-o", directory / "libBetterAppleCore.dylib"])
    link = ["-parse-as-library", "-I", directory, "-L", directory, "-lBetterAppleCore",
            "-Xlinker", "-rpath", "-Xlinker", directory]
    services = sorted((root / "Sources/BetterApple/Services").glob("*.swift"))
    shared = sorted((root / "Sources/BetterApple/Shared").rglob("*.swift"))
    modules = sorted(path for path in (root / "Sources/BetterApple/Features/DynamicIsland").rglob("*.swift") if path.name not in {"IslandManager.swift", "IslandView.swift"})
    checks = {
        "services": (services, "service-smoke.swift"),
        "productivity": (services, "productivity-smoke.swift"),
        "dock": (shared + sorted((root / "Sources/BetterApple/Features/Dock").glob("*.swift")), "dock-smoke.swift"),
        "widgets": (services + shared + modules +
                    sorted((root / "Sources/BetterApple/Features/Widgets").glob("*.swift")), "widget-smoke.swift"),
    }
    checks["dock-motion"] = (checks["dock"][0], "dock-motion-smoke.swift")
    checks["widget-motion"] = (checks["widgets"][0], "widget-motion-smoke.swift")
    checks["notch-shape"] = ([root / "Sources/BetterApple/Features/DynamicIsland/IslandState.swift",
                              root / "Sources/BetterApple/Features/DynamicIsland/CameraCapView.swift"], "notch-shape-smoke.swift")
    for name, (sources, script) in checks.items():
        if selection not in {"all", name}:
            continue
        print(f"Checking {name}…", flush=True)
        executable = directory / f"{name}-smoke"
        run(compiler + link + sources + [root / "Scripts" / script, "-o", executable])
        run([executable])
    print("Native checks passed.", flush=True)
