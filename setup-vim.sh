#!/usr/bin/env bash
set -euo pipefail

# Installs Vim config, vim-plug, and configured Vim plugins.
# Usage: ./setup-vim.sh

SCRIPT_NAME="$(basename "$0")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIMRC_SOURCE="${REPO_DIR}/.vimrc"
VIMRC_TARGET="${HOME}/.vimrc"
VIM_PLUG_PATH="${HOME}/.vim/autoload/plug.vim"
VIM_PLUG_URL="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
    return
  fi
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return
  fi
  if command -v pacman >/dev/null 2>&1; then
    echo "pacman"
    return
  fi
  echo ""
}

install_base_packages() {
  local needed=()
  for cmd in vim git curl; do
    command -v "${cmd}" >/dev/null 2>&1 || needed+=("${cmd}")
  done

  if [[ ${#needed[@]} -eq 0 ]]; then
    log "vim, git, and curl already installed; skipping package manager."
    return
  fi

  log "Missing: ${needed[*]}"

  local pkg_manager
  pkg_manager="$(detect_pkg_manager)"

  case "${pkg_manager}" in
    apt)
      log "Installing Vim base packages with apt..."
      sudo apt-get install -y "${needed[@]}" ca-certificates
      ;;
    dnf)
      log "Installing Vim base packages with dnf..."
      sudo dnf install -y "${needed[@]}" ca-certificates
      ;;
    pacman)
      log "Installing Vim base packages with pacman..."
      sudo pacman -S --needed --noconfirm "${needed[@]}" ca-certificates
      ;;
    *)
      log "No supported package manager detected (apt/dnf/pacman)."
      log "Install vim, git, and curl manually, then re-run ${SCRIPT_NAME}."
      exit 1
      ;;
  esac
}

link_vimrc() {
  if [[ ! -f "${VIMRC_SOURCE}" ]]; then
    log "Repo Vim config not found at ${VIMRC_SOURCE}."
    exit 1
  fi

  if [[ -L "${VIMRC_TARGET}" ]]; then
    local current_target
    current_target="$(readlink "${VIMRC_TARGET}")"
    if [[ "${current_target}" == "${VIMRC_SOURCE}" ]]; then
      log "${VIMRC_TARGET} already points to repo .vimrc."
      return
    fi
  elif [[ -e "${VIMRC_TARGET}" ]]; then
    local backup_path
    backup_path="${VIMRC_TARGET}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "${VIMRC_TARGET}" "${backup_path}"
    log "Backed up existing .vimrc to ${backup_path}."
  fi

  ln -sfn "${VIMRC_SOURCE}" "${VIMRC_TARGET}"
  log "Linked ${VIMRC_TARGET} to ${VIMRC_SOURCE}."
}

install_vim_plug() {
  mkdir -p "$(dirname "${VIM_PLUG_PATH}")"

  if [[ -f "${VIM_PLUG_PATH}" ]]; then
    log "vim-plug already installed."
    return
  fi

  log "Installing vim-plug..."
  curl -fLo "${VIM_PLUG_PATH}" --create-dirs "${VIM_PLUG_URL}"
}

install_vim_plugins() {
  log "Installing/updating Vim plugins from ${VIMRC_TARGET}..."
  vim -Nu "${VIMRC_TARGET}" -n -es -S <(printf '%s\n' 'PlugInstall --sync' 'qa')
}

main() {
  install_base_packages
  link_vimrc
  install_vim_plug
  install_vim_plugins

  log "Vim setup complete."
}

main "$@"
