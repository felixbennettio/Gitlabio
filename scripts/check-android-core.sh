#!/usr/bin/env bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_tmp="$(mktemp -d)"
trap 'rm -rf "$task_tmp"' EXIT
mkdir -p "$task_tmp/project/gradle/wrapper"
cp "$task_root/android/gradlew" "$task_tmp/project/gradlew"
cp "$task_root/android/gradle/wrapper/"* "$task_tmp/project/gradle/wrapper/"
cp -R "$task_root/android/core" "$task_tmp/project/core"
cp -R "$task_root/contracts" "$task_tmp/contracts"
cat > "$task_tmp/project/settings.gradle.kts" <<'GRADLE'
pluginManagement { repositories { mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositories { mavenCentral() } }
rootProject.name = "GitlabioCoreCheck"
include(":core")
GRADLE
cat > "$task_tmp/project/build.gradle.kts" <<'GRADLE'
plugins {
    kotlin("jvm") version "2.1.21" apply false
    kotlin("plugin.serialization") version "2.1.21" apply false
}
GRADLE
cd "$task_tmp/project"
GRADLE_USER_HOME="$task_tmp/gradle-home" ./gradlew --no-daemon --console=plain :core:test
