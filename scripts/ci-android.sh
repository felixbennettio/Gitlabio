#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_tmp="$(mktemp -d)"
trap 'rm -rf "$task_tmp"' EXIT
mkdir -p "$task_tmp/source" "$task_root/dist/android" "$task_root/reports/android/tests"
cp -R "$task_root/contracts" "$task_tmp/contracts"
tar -C "$task_root/android" --exclude=.gradle --exclude=.kotlin --exclude=build -cf - . | tar -C "$task_tmp/source" -xf -
# Reuse runner dependency artifacts; only version-specific generated script
# state is isolated to avoid the observed shared Kotlin DSL metadata failure.
task_existing_gradle_home="${GRADLE_USER_HOME:-$HOME/.gradle}"
task_gradle_init=()
shopt -s nullglob
for task_init in "$task_existing_gradle_home/init.gradle" "$task_existing_gradle_home/init.gradle.kts" \
  "$task_existing_gradle_home"/init.d/*.gradle "$task_existing_gradle_home"/init.d/*.gradle.kts; do
  if [ -f "$task_init" ]; then task_gradle_init+=(--init-script "$task_init"); fi
done
export GRADLE_USER_HOME="$task_tmp/gradle-home"
task_dependency_cache="$task_existing_gradle_home/caches/modules-2"
mkdir -p "$GRADLE_USER_HOME/caches" "$task_dependency_cache"
ln -s "$task_dependency_cache" "$GRADLE_USER_HOME/caches/modules-2"
echo "Using runner dependency cache: $task_dependency_cache"
du -sh "$task_dependency_cache"
python3 "$task_root/scripts/check-dependency-cache.py" "$task_dependency_cache" "$task_tmp/corrupt-artifacts"
if [ -f "$task_existing_gradle_home/gradle.properties" ]; then
  ln -s "$task_existing_gradle_home/gradle.properties" "$GRADLE_USER_HOME/gradle.properties"
fi
task_gradle_command=./gradlew
for task_gradle_binary in "$task_existing_gradle_home"/wrapper/dists/gradle-8.9-bin/*/gradle-8.9/bin/gradle; do
  if [ -x "$task_gradle_binary" ]; then task_gradle_command="$task_gradle_binary"; break; fi
done
cd "$task_tmp/source"
for task_attempt in 1 2 3; do
  set +e
  "$task_gradle_command" --no-daemon --console=plain --project-cache-dir "$task_tmp/project-cache" \
    "${task_gradle_init[@]}" --continue :core:test :app:testDebugUnitTest :app:assembleDebug :app:lintDebug 2>&1 | tee "$task_tmp/gradle-$task_attempt.log"
  task_status=${PIPESTATUS[0]}
  set -e
  if [ "$task_status" -eq 0 ] || [ "$task_attempt" -eq 3 ]; then break; fi
  if python3 "$task_root/scripts/dependency-network-failure.py" "$task_tmp/gradle-$task_attempt.log"; then
    echo "Transient dependency download failure; retrying with this job's existing cache (attempt $((task_attempt + 1))/3)."
    sleep "$((task_attempt * 5))"
  else
    break
  fi
done
if [ -d core/build/test-results/test ]; then cp core/build/test-results/test/*.xml "$task_root/reports/android/tests/"; fi
if [ -d app/build/test-results/testDebugUnitTest ]; then cp app/build/test-results/testDebugUnitTest/*.xml "$task_root/reports/android/tests/"; fi
# Roborazzi screenshots of the demo data set, for reviewing the UI from the job artifacts.
if [ -d app/build/outputs/roborazzi ]; then cp -R app/build/outputs/roborazzi "$task_root/reports/android/screenshots"; fi
if [ -d app/build/reports ]; then cp -R app/build/reports "$task_root/reports/android/lint"; fi
if [ -d app/build/outputs/apk/debug ]; then cp app/build/outputs/apk/debug/*.apk "$task_root/dist/android/"; fi
exit "$task_status"
