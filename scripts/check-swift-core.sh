#!/usr/bin/env bash
# Runs the GitLabCore Swift Testing suite. Works with Command Line Tools only (no Xcode).
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_tmp="$(mktemp -d)"
trap 'rm -rf "$task_tmp"' EXIT
export CLANG_MODULE_CACHE_PATH="$task_tmp/clang"
swift test --package-path "$task_root/apple/GitLabCore" \
  --scratch-path "$task_tmp/build" --cache-path "$task_tmp/cache" --disable-sandbox "$@"
