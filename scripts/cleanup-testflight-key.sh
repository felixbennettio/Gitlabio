#!/usr/bin/env bash
set -euo pipefail
# Defense in depth if the publishing shell was terminated during cancellation.
# This job-specific name is only used by Gitlabio's own generated key files.
if [ -z "${CI_JOB_ID:-}" ]; then exit 0; fi
shopt -s nullglob
for task_key in "$HOME/Library/Application Support/Gitlabio/Signing/Gitlabio-${CI_JOB_ID}-"*.p8; do
  if [ -f "$task_key" ] && [ ! -L "$task_key" ]; then rm -f "$task_key"; fi
done
