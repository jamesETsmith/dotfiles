#!/usr/bin/env bash
set -euo pipefail

# Installs the repo's shared LLM instruction files into ~/.agents via symlinks.
# Usage: ./install-llm-agents.sh

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLM_DIR="${SCRIPT_DIR}/llm"
AGENTS_DIR="${HOME}/.agents"

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

link_path() {
  local source_path="$1"
  local target_path="$2"

  if [[ ! -e "${source_path}" ]]; then
    log "Source path not found: ${source_path}"
    exit 1
  fi

  if [[ -L "${target_path}" ]]; then
    local current_target
    current_target="$(readlink "${target_path}")"

    if [[ "${current_target}" == "${source_path}" ]]; then
      log "Symlink already correct: ${target_path}"
      return
    fi

    rm "${target_path}"
    ln -s "${source_path}" "${target_path}"
    log "Updated symlink: ${target_path} -> ${source_path}"
    return
  fi

  if [[ -e "${target_path}" ]]; then
    log "Refusing to replace existing non-symlink path: ${target_path}"
    exit 1
  fi

  ln -s "${source_path}" "${target_path}"
  log "Created symlink: ${target_path} -> ${source_path}"
}

main() {
  mkdir -p "${AGENTS_DIR}"

  link_path "${LLM_DIR}/AGENTS.md" "${AGENTS_DIR}/AGENTS.md"
  link_path "${LLM_DIR}/skills" "${AGENTS_DIR}/skills"

  log "Installed LLM files into ${AGENTS_DIR}"
}

main "$@"
