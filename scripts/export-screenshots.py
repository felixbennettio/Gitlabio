"""Copy UI-test screenshot attachments exported by xcresulttool to readable file names."""
import json
import re
import shutil
import sys
from pathlib import Path

source, target = Path(sys.argv[1]), Path(sys.argv[2])
target.mkdir(parents=True, exist_ok=True)
manifest = json.loads((source / "manifest.json").read_text())
count = 0
for test in manifest:
    for attachment in test.get("attachments", []):
        name = attachment.get("suggestedHumanReadableName") or attachment["exportedFileName"]
        # "home-light_0_<UUID>.png" -> "home-light.png"
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}", "", name)
        shutil.copy(source / attachment["exportedFileName"], target / name)
        count += 1
if count == 0:
    raise SystemExit("No screenshots were exported")
print(f"Exported {count} screenshots to {target}")
