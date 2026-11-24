"""Retain Gradle artifacts, quarantining only demonstrably corrupt entries."""
import hashlib
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

artifacts = Path(sys.argv[1]) / "files-2.1"
quarantine = Path(sys.argv[2])
quarantine.mkdir(parents=True, exist_ok=True)
valid = invalid = 0
for path in artifacts.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    try:
        # Gradle's files-2.1 store addresses downloaded files by SHA-1. This
        # detects truncated/zero-filled JARs and metadata without discarding
        # healthy artifacts or rebuilding the shared binary index ourselves.
        if re.fullmatch(r"[0-9a-f]{40}", path.parent.name):
            checksum = hashlib.sha1()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    checksum.update(chunk)
            if checksum.hexdigest() != path.parent.name:
                raise ValueError("Content checksum mismatch")
        if path.suffix == ".pom":
            root = ET.parse(path).getroot()
            if root.tag not in ("project", "{http://maven.apache.org/POM/4.0.0}project"):
                raise ValueError("Not a Maven POM")
        elif path.suffix == ".module":
            with path.open(encoding="utf-8") as stream:
                metadata = json.load(stream)
            if not isinstance(metadata, dict) or "formatVersion" not in metadata:
                raise ValueError("Not Gradle module metadata")
        valid += 1
    except (ET.ParseError, ValueError, UnicodeError):
        name = hashlib.sha256(str(path).encode()).hexdigest() + path.suffix
        shutil.move(str(path), str(quarantine / name))
        invalid += 1
        print("Quarantined corrupt dependency:", path.relative_to(artifacts))
print(f"Runner dependency cache: {valid} valid files retained; {invalid} corrupt files quarantined")
