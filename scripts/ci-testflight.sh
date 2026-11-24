#!/usr/bin/env bash
set -euo pipefail
umask 077
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_tmp="$(mktemp -d)"
task_key=""
cleanup() {
  local task_cleanup_status=0
  if [ -n "$task_key" ]; then rm -f "$task_key" || task_cleanup_status=$?; fi
  if [ -f "$task_tmp/export.log" ]; then
    python3 "$task_root/scripts/cleanup-testflight-files.py" export "$task_tmp/export.log" || task_cleanup_status=$?
  fi
  rm -rf "$task_tmp" || task_cleanup_status=$?
  return "$task_cleanup_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for task_setting in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_PRIVATE_KEY APPLE_TEAM_ID; do
  if [ -z "${!task_setting:-}" ]; then echo "Missing protected publishing variable: $task_setting" >&2; exit 1; fi
done
if [ "${CI_COMMIT_REF_PROTECTED:-false}" != true ]; then echo 'TestFlight requires a protected ref.' >&2; exit 1; fi
# Location approved by the owner on 2026-10-28. No private key is placed in
# the checkout, .git, build artifacts, or mktemp directory.
task_signing_dir="$HOME/Library/Application Support/Gitlabio/Signing"
if [ -L "$task_signing_dir" ]; then echo 'Signing directory must not be a symlink.' >&2; exit 1; fi
mkdir -p "$task_signing_dir"
if [ "$(stat -f '%u' "$task_signing_dir")" != "$(id -u)" ]; then echo 'Signing directory ownership mismatch.' >&2; exit 1; fi
chmod 700 "$task_signing_dir"
task_key_candidate="$task_signing_dir/Gitlabio-${CI_JOB_ID}-$(uuidgen).p8"
export GITLABIO_ASC_KEY_PATH="$task_key_candidate"
python3 - <<'PY'
import os,base64
raw=os.environ['APP_STORE_CONNECT_PRIVATE_KEY'].encode()
if not raw.startswith(b'-----BEGIN '):
    raw=base64.b64decode(raw,validate=True)
if b'PRIVATE KEY-----' not in raw:
    raise SystemExit('App Store private key format is invalid')
path=os.environ['GITLABIO_ASC_KEY_PATH']
fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
try:
    with os.fdopen(fd,'wb') as stream:stream.write(raw)
except BaseException:
    os.unlink(path)
    raise
PY
task_key="$task_key_candidate"
unset APP_STORE_CONNECT_PRIVATE_KEY
export CLANG_MODULE_CACHE_PATH="$task_tmp/clang"
mkdir -p "$task_tmp/tmp"
export TMPDIR="$task_tmp/tmp/"
xcrun swiftc -parse-as-library "$task_root/scripts/app-store-connect.swift" -o "$task_tmp/app-store-connect"
if [ "${GITLABIO_PUBLISH_OPERATION:-upload}" = distribute ]; then
  mkdir -p "$task_root/dist/testflight"
  "$task_tmp/app-store-connect" distribute "$task_root/dist/testflight/distribution.json"
  rm -f "$task_key"
  if [ -e "$task_key" ]; then echo 'Publishing key cleanup failed.' >&2; exit 1; fi
  task_key=""
  python3 - "$task_root/dist/testflight/distribution.json" <<'PY'
import json,sys
with open(sys.argv[1]) as stream:result=json.load(stream)
result['privateKeyFileRemoved']=True
with open(sys.argv[1],'w') as stream:json.dump(result,stream,indent=2)
PY
  exit 0
fi
"$task_tmp/app-store-connect" preflight "$task_tmp/preflight.json"
GITLABIO_BUILD_NUMBER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["buildNumber"])' "$task_tmp/preflight.json")"
export GITLABIO_BUILD_NUMBER
xcodebuild archive -project "$task_root/apple/Gitlabio.xcodeproj" -scheme Gitlabio \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$task_tmp/Gitlabio.xcarchive" -derivedDataPath "$task_tmp/derived" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$task_key" -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$GITLABIO_BUILD_NUMBER"
python3 - "$task_tmp/ExportOptions.plist" <<'PY'
import os,plistlib,sys
with open(sys.argv[1],'wb') as stream:
    plistlib.dump({'method':'app-store-connect','destination':'upload','teamID':os.environ['APPLE_TEAM_ID'],
                  'signingStyle':'automatic','manageAppVersionAndBuildNumber':False,'uploadSymbols':True},stream)
PY
xcodebuild -exportArchive -archivePath "$task_tmp/Gitlabio.xcarchive" \
  -exportOptionsPlist "$task_tmp/ExportOptions.plist" -exportPath "$task_tmp/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$task_key" -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID" 2>&1 | tee "$task_tmp/export.log"
mkdir -p "$task_root/dist/testflight"
python3 - "$task_tmp/preflight.json" "$task_root/dist/testflight/upload.json" <<'PY'
import datetime,json,os,sys
with open(sys.argv[1]) as stream:result=json.load(stream)
result.update(uploadStatus='accepted',commit=os.environ['CI_COMMIT_SHA'],
              acceptedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
with open(sys.argv[2],'w') as stream:json.dump(result,stream,indent=2)
PY
"$task_tmp/app-store-connect" wait "$task_root/dist/testflight/result.json"
