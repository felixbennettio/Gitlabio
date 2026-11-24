"""Remove only this app's explicitly identified CI publishing intermediates."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


def owned(path):
    if path.is_symlink() or path.stat().st_uid != os.getuid():
        raise ValueError("Publishing cleanup target has an unexpected owner or symlink")


def remove_distribution_log(root, name):
    if not re.fullmatch(r"Gitlabio_[0-9_-]+\.[0-9]+\.xcdistributionlogs", name):
        raise ValueError("Unexpected distribution log name")
    target = root / name
    if not target.exists() and not target.is_symlink():
        return 0
    owned(target)
    if not target.is_dir():
        raise ValueError("Distribution log must be a directory")
    shutil.rmtree(target)
    return 1


def system_temp():
    return Path(subprocess.check_output(["getconf", "DARWIN_USER_TEMP_DIR"], text=True).strip()).resolve()


def main():
    root = system_temp()
    if sys.argv[1] == "export":
        text = Path(sys.argv[2]).read_text(errors="replace")
        count = 0
        for item in set(re.findall(r'Created bundle at path "([^"\n]+\.xcdistributionlogs)"', text)):
            target = Path(item)
            if target.parent.resolve() != root:
                raise ValueError("Xcode distribution log is outside the user temp directory")
            count += remove_distribution_log(root, target.name)
        print(f"Removed {count} Xcode distribution log directories")
    elif sys.argv[1] == "audit":
        if os.environ.get("CI_COMMIT_REF_PROTECTED") != "true":
            raise ValueError("Release cleanup audit requires a protected ref")
        job = os.environ["GITLABIO_RELEASE_JOB_ID"]
        if not re.fullmatch(r"[0-9]+", job):
            raise ValueError("Invalid release job ID")
        signing = Path.home() / "Library/Application Support/Gitlabio/Signing"
        removed_keys = 0
        if signing.exists() or signing.is_symlink():
            owned(signing)
            for key in signing.glob(f"Gitlabio-{job}-*.p8"):
                owned(key)
                if not key.is_file():
                    raise ValueError("Unexpected signing key target")
                key.unlink()
                removed_keys += 1
            if list(signing.glob(f"Gitlabio-{job}-*.p8")):
                raise ValueError("Release key cleanup failed")
        logs = remove_distribution_log(root, os.environ["GITLABIO_DISTRIBUTION_LOG_BASENAME"])
        name = os.environ["GITLABIO_RELEASE_TEMP_BASENAME"]
        if not re.fullmatch(r"tmp\.[A-Za-z0-9]+", name):
            raise ValueError("Invalid release temp directory")
        target = root / name
        if target.exists() or target.is_symlink():
            owned(target)
            # Never remove an arbitrary system temp directory. A surviving
            # release directory must identify this app before it is removed.
            proof = json.loads((target / "preflight.json").read_text())
            if proof.get("bundleID") != "io.routeforge.gitlabio":
                raise ValueError("Release temp directory does not identify Gitlabio")
            shutil.rmtree(target)
        result = {"releaseJobID": int(job), "signingKeysRemoved": removed_keys,
                  "signingKeysRemaining": 0, "distributionLogsRemoved": logs,
                  "releaseTempDirectoryRemaining": False}
        output = Path("dist/testflight-cleanup/result.json")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result))
    else:
        raise ValueError("Unknown cleanup operation")


if __name__ == "__main__":
    main()
