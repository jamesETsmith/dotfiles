#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf "${temp_dir}"' EXIT
mkdir -p "${temp_dir}/home/.config/crush" "${temp_dir}/home/.config/fish"
printf '{}\n' >"${temp_dir}/home/.config/crush/crush.json"
printf '\n' >"${temp_dir}/home/.config/fish/config.local.fish"

if HOME="${temp_dir}/home" bash -x "${repo_dir}/setup-remote-crush.sh" \
  -y -J invalid.jump.example --ssh-arg -o \
  --ssh-arg StrictHostKeyChecking=no --crush-version v0.91.0 \
  invalid.remote.example >"${temp_dir}/trace.log" 2>&1; then
  exit 1
fi

trace="$(cat "${temp_dir}/trace.log")"
[[ "${trace}" == *"ssh -o StrictHostKeyChecking=no -J invalid.jump.example invalid.remote.example"* ]]
