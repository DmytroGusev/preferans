#!/usr/bin/env python3
"""Tie simulator captures to the exact app, engine, fixtures, and build settings."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]


def source_manifest():
    files = []
    for name in ("Preferans", "Sources", "PreferansUITests"):
        files.extend(p for p in (ROOT / name).rglob("*") if p.is_file() and p.name != ".DS_Store")
    files.extend(p for p in (ROOT / "Preferans.xcodeproj").rglob("*")
                 if p.is_file() and (p.name == "project.pbxproj" or p.suffix == ".xcscheme"))
    files.extend(ROOT / name for name in ("Package.swift", "Package.resolved") if (ROOT / name).is_file())
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(files)}
    digest = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    return {"schema": 1, "sourceDigest": digest, "files": hashes}


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(path)


def check(path):
    try:
        recorded = json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        print(f"[screens] No source record at {path}; rebuild with bin/screens.", file=sys.stderr)
        return False
    current = source_manifest()
    if recorded.get("sourceDigest") == current["sourceDigest"]:
        return True
    before = recorded.get("files", {})
    changed = [p for p in sorted(before.keys() | current["files"].keys())
               if before.get(p) != current["files"].get(p)]
    print("[screens] Source differs from the recorded build/capture:", file=sys.stderr)
    for name in changed[:8]:
        print(f"  {name}", file=sys.stderr)
    print("[screens] Re-render with bin/screens.", file=sys.stderr)
    return False


def main():
    command = sys.argv[1]
    path = Path(sys.argv[2])
    if command == "stamp":
        data = source_manifest()
        data["builtAt"] = datetime.now(timezone.utc).isoformat()
        data["commit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        write(path, data)
    elif command == "check":
        return 0 if check(path) else 3
    elif command == "capture":
        data = json.loads(path.read_text())
        destination = Path(sys.argv[3])
        data.update(capturedAt=datetime.now(timezone.utc).isoformat(),
                    testExitCode=int(sys.argv[4]), destination=sys.argv[5], tests=sys.argv[6:])
        write(destination, data)
    else:
        raise SystemExit(f"Unknown command: {command}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
