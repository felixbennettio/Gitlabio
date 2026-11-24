#!/usr/bin/env bash
# Type-checks the SwiftUI app sources against the macOS SDK (Command Line Tools only).
# iOS-only APIs are wrapped in `#if os(iOS)`, so this catches most compile errors without
# Xcode. The real iOS build still runs in CI (`scripts/ci-apple.sh`).
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="${GITLABIO_TYPECHECK_DIR:-$(mktemp -d)}"
if [ -z "${GITLABIO_TYPECHECK_DIR:-}" ]; then trap 'rm -rf "$task_build"' EXIT; fi
export CLANG_MODULE_CACHE_PATH="$task_build/clang"
# The macOS 27 SDK implements @State with a macro plugin that ships only with Xcode, so
# prefer a macOS 26 SDK from Command Line Tools when one is installed.
task_sdk="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | sort -V | tail -1)"
export SDKROOT="${task_sdk:-$(xcrun --show-sdk-path)}"
swift build --package-path "$task_root/apple/GitLabCore" --scratch-path "$task_build/core" --disable-sandbox -q
modules="$(find "$task_build/core" -name 'GitLabCore.swiftmodule' -path '*Products/Debug/*' | head -1)"
find "$task_root/apple/Gitlabio" -name '*.swift' -print0 | xargs -0 xcrun swiftc -typecheck \
  -target arm64-apple-macos26.0 -sdk "$SDKROOT" \
  -I "$(dirname "$modules")" -module-cache-path "$task_build/clang" -swift-version 5 "$@"
echo "Type check passed"
