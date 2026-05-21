#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: ci/measure-step.sh <step-name> <command> [args...]

Runs a command, records elapsed wall-clock time, and appends a JSONL timing
record for CI artifacts.
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 2
fi

step_name="$1"
shift

timings_dir="${TIMINGS_DIR:-.ci-timings}"
timings_file="${TIMINGS_FILE:-${timings_dir}/timings.jsonl}"
mkdir -p "${timings_dir}"

printf '[measure-step] starting: %s\n' "${step_name}"

start_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
start_ns="$(date +%s%N)"

set +e
"$@"
status=$?
set -e

end_ns="$(date +%s%N)"
end_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
duration_ms=$(((end_ns - start_ns) / 1000000))
printf -v duration_s '%d.%03d' "$((duration_ms / 1000))" "$((duration_ms % 1000))"

command_text="$(printf '%q ' "$@")"

python3 - \
  "${timings_file}" \
  "${step_name}" \
  "${command_text}" \
  "${status}" \
  "${duration_ms}" \
  "${start_time}" \
  "${end_time}" <<'PY'
import json
import os
import sys

record = {
    "step": sys.argv[2],
    "command": sys.argv[3].strip(),
    "status": int(sys.argv[4]),
    "duration_ms": int(sys.argv[5]),
    "start_time": sys.argv[6],
    "end_time": sys.argv[7],
    "commit": os.environ.get("GITHUB_SHA", ""),
    "ref": os.environ.get("GITHUB_REF_NAME", ""),
    "workflow": os.environ.get("GITHUB_WORKFLOW", ""),
    "job": os.environ.get("GITHUB_JOB", ""),
}

with open(sys.argv[1], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, sort_keys=True) + "\n")
PY

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    printf '### Timing: %s\n\n' "${step_name}"
    printf '| Metric | Value |\n'
    printf '| --- | --- |\n'
    printf "| Duration | \`%ss\` |\n" "${duration_s}"
    printf "| Exit status | \`%s\` |\n\n" "${status}"
  } >>"${GITHUB_STEP_SUMMARY}"
fi

printf '[measure-step] finished: %s in %ss (exit %s)\n' "${step_name}" "${duration_s}" "${status}"
exit "${status}"
