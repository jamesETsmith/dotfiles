#!/usr/bin/env bash
set -euo pipefail

# Installs Rust and common CLI tooling built with cargo.
# Usage: ./setup-rust-env.sh [--install-build-deps]

SCRIPT_NAME="$(basename "$0")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
RUSTUP_INIT_URL="https://sh.rustup.rs"
CARGO_BINSTALL_INSTALLER_URL="https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh"
INSTALL_BUILD_DEPS=0
RUST_TOOLS=(
  ripgrep
  bottom
  bat
  eza
  hyperfine
  sd
  tokei
  git-delta
  zellij
)
declare -A RUST_TOOL_COMMANDS=(
  [ripgrep]=rg
  [bottom]=btm
  [bat]=bat
  [eza]=eza
  [hyperfine]=hyperfine
  [sd]=sd
  [tokei]=tokei
  ["git-delta"]=delta
  [zellij]=zellij
)

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

usage() {
  cat <<EOF
Usage: ./setup-rust-env.sh [--install-build-deps]

Options:
  --install-build-deps  Install system packages required to build some cargo crates.
  -h, --help            Show this help message.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-build-deps)
        INSTALL_BUILD_DEPS=1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        log "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
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

install_build_deps() {
  local pkg_manager
  pkg_manager="$(detect_pkg_manager)"

  case "${pkg_manager}" in
    apt)
      log "Installing build dependencies with apt..."
      sudo apt-get update
      sudo apt-get install -y curl git build-essential pkg-config libssl-dev cmake
      ;;
    dnf)
      log "Installing build dependencies with dnf..."
      sudo dnf install -y curl git gcc gcc-c++ make pkgconfig openssl-devel cmake
      ;;
    pacman)
      log "Installing build dependencies with pacman..."
      sudo pacman -Syu --noconfirm curl git base-devel pkgconf openssl cmake
      ;;
    *)
      log "No supported package manager detected (apt/dnf/pacman)."
      log "Install curl, a C/C++ build toolchain, pkg-config, and OpenSSL dev libs manually."
      ;;
  esac
}

can_execute_in_dir() {
  local dir="$1"
  local test_file

  test_file="$(mktemp "${dir}/rustup-exec-test.XXXXXX")" || return 1
  printf '#!/bin/sh\nexit 0\n' >"${test_file}"
  chmod +x "${test_file}"
  if "${test_file}" 2>/dev/null; then
    rm -f "${test_file}"
    return 0
  fi

  rm -f "${test_file}"
  return 1
}

ensure_executable_tmpdir() {
  local exec_tmp="${HOME}/.cache/tmp"
  local current_tmp="${TMPDIR:-/tmp}"

  if can_execute_in_dir "${current_tmp}"; then
    return
  fi

  mkdir -p "${exec_tmp}"
  if ! can_execute_in_dir "${exec_tmp}"; then
    log "No executable temporary directory found (checked ${current_tmp} and ${exec_tmp})."
    exit 1
  fi

  export TMPDIR="${exec_tmp}"
  log "Using TMPDIR=${TMPDIR} because ${current_tmp} cannot execute binaries (noexec)."
}

resolve_cargo_target_dir() {
  if [[ -n "${CARGO_TARGET_DIR:-}" ]]; then
    printf '%s\n' "${CARGO_TARGET_DIR}"
    return
  fi
  printf '%s\n' "${CARGO_HOME:-${HOME}/.cargo}/target"
}

ensure_executable_cargo_target_dir() {
  local exec_target="${HOME}/.cache/cargo-target"
  local current_target

  current_target="$(resolve_cargo_target_dir)"

  mkdir -p "${current_target}"
  if can_execute_in_dir "${current_target}"; then
    return
  fi

  mkdir -p "${exec_target}"
  if ! can_execute_in_dir "${exec_target}"; then
    log "No executable cargo target directory found (checked ${current_target} and ${exec_target})."
    exit 1
  fi

  export CARGO_TARGET_DIR="${exec_target}"
  log "Using CARGO_TARGET_DIR=${CARGO_TARGET_DIR} because ${current_target} cannot execute binaries (noexec)."
}

ensure_cargo_in_path() {
  if command -v cargo >/dev/null 2>&1; then
    return
  fi

  if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    log "cargo is still not available in PATH."
    exit 1
  fi
}

install_rust() {
  if command -v rustup >/dev/null 2>&1; then
    log "rustup already installed; updating stable toolchain..."
    rustup update stable
    ensure_cargo_in_path
    return
  fi

  log "Installing rustup and stable Rust..."
  ensure_executable_tmpdir
  curl --proto '=https' --tlsv1.2 -fsSL "${RUSTUP_INIT_URL}" | sh -s -- -y --profile minimal --default-toolchain stable
  ensure_cargo_in_path
}

install_cargo_binstall() {
  if command -v cargo-binstall >/dev/null 2>&1; then
    log "cargo-binstall already installed."
    return
  fi

  log "Installing cargo-binstall from prebuilt release..."
  if curl --proto '=https' --tlsv1.2 -fsSL "${CARGO_BINSTALL_INSTALLER_URL}" | bash; then
    ensure_cargo_in_path
    if command -v cargo-binstall >/dev/null 2>&1; then
      return
    fi
    log "cargo-binstall installer completed, but cargo-binstall is not on PATH."
  else
    log "Prebuilt cargo-binstall installer failed."
  fi

  log "Falling back to cargo install --locked cargo-binstall..."
  cargo install --locked cargo-binstall
}

install_rust_tool() {
  local crate="$1"
  local command_name="${RUST_TOOL_COMMANDS[${crate}]:-${crate}}"

  if command -v "${command_name}" >/dev/null 2>&1; then
    log "${crate} already installed as ${command_name}; skipping."
    return
  fi

  log "Installing ${crate} with cargo-binstall..."
  if cargo binstall --no-confirm "${crate}"; then
    if command -v "${command_name}" >/dev/null 2>&1; then
      return
    fi
    log "cargo-binstall reported success but did not provide ${command_name}."
    return 1
  fi

  log "cargo-binstall could not install ${crate}; falling back to cargo install --locked..."
  cargo install --locked "${crate}"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log "Installation of ${crate} completed without providing ${command_name}."
    return 1
  fi
}

install_yazi() {
  if command -v yazi >/dev/null 2>&1 && command -v ya >/dev/null 2>&1; then
    log "Yazi already installed; skipping."
    return
  fi

  log "Installing Yazi with cargo-binstall..."
  if cargo binstall --no-confirm yazi-fm && command -v yazi >/dev/null 2>&1 && command -v ya >/dev/null 2>&1; then
    return
  fi

  log "cargo-binstall did not provide both yazi and ya; falling back to cargo install --force yazi-build..."
  cargo install --force yazi-build

  if ! command -v yazi >/dev/null 2>&1 || ! command -v ya >/dev/null 2>&1; then
    log "Yazi installation completed without providing both yazi and ya."
    return 1
  fi
}

install_rust_tools() {
  local crate
  ensure_executable_tmpdir
  ensure_executable_cargo_target_dir
  install_cargo_binstall

  for crate in "${RUST_TOOLS[@]}"; do
    install_rust_tool "${crate}"
  done
  install_yazi
}

ensure_cargo_bin_in_path_or_shell_rcs() {
  local cargo_bin="${HOME}/.cargo/bin"
  local zshrc_path="${HOME}/.zshrc"
  local cargo_path_zsh="export PATH=\"\$HOME/.cargo/bin:\$PATH\""
  local fish_config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/fish"
  local fish_config_path="${fish_config_dir}/config.fish"
  local cargo_path_fish="fish_add_path -m \$HOME/.cargo/bin"

  if [[ ":${PATH}:" == *":${cargo_bin}:"* ]]; then
    log "cargo bin directory already present in current PATH."
  else
    export PATH="${cargo_bin}:${PATH}"
    log "Added ${cargo_bin} to current PATH for this session."
  fi

  # Update zshrc
  if [[ -f "${zshrc_path}" ]]; then
    if ! rg -q '(\.cargo/bin|\.cargo/env)' "${zshrc_path}"; then
      printf '\n%s\n' "${cargo_path_zsh}" >>"${zshrc_path}"
      log "Added cargo PATH snippet to ${zshrc_path}."
    else
      log "Cargo PATH setup already present in ${zshrc_path}."
    fi
  else
    printf '%s\n' "${cargo_path_zsh}" >"${zshrc_path}"
    log "Created ${zshrc_path} with cargo PATH snippet."
  fi

  # Update fish config if it exists or if fish is installed
  if command -v fish >/dev/null 2>&1 || [[ -d "${fish_config_dir}" ]]; then
    mkdir -p "${fish_config_dir}"
    touch "${fish_config_path}"
    if ! rg -q '\.cargo/bin' "${fish_config_path}"; then
      printf '\nif status is-interactive\n  %s\nend\n' "${cargo_path_fish}" >>"${fish_config_path}"
      log "Added cargo PATH snippet to ${fish_config_path}."
    else
      log "Cargo PATH setup already present in ${fish_config_path}."
    fi
  fi
}

write_file_if_missing() {
  local path="$1"
  local description="$2"
  local content="$3"

  if [[ -f "${path}" ]]; then
    log "${description} already exists at ${path}; leaving as-is."
    return
  fi

  mkdir -p "$(dirname "${path}")"
  printf '%s\n' "${content}" >"${path}"
  log "Created ${description} at ${path}."
}

link_file() {
  local source_path="$1"
  local target_path="$2"
  local description="$3"

  mkdir -p "$(dirname "${target_path}")"

  if [[ -L "${target_path}" ]]; then
    local current_target
    current_target="$(readlink "${target_path}")"
    if [[ "${current_target}" == "${source_path}" ]]; then
      log "${description} already points to repo file."
      return
    fi
  elif [[ -e "${target_path}" ]]; then
    local backup_path
    backup_path="${target_path}.bak.$(date +%Y%m%d-%H%M%S)"
    mv "${target_path}" "${backup_path}"
    log "Backed up existing ${description} to ${backup_path}."
  fi

  ln -sfn "${source_path}" "${target_path}"
  log "Linked ${description} to ${source_path}."
}

configure_ripgrep() {
  local rg_config_path="${CONFIG_HOME}/ripgrep/config"
  write_file_if_missing \
    "${rg_config_path}" \
    "ripgrep config" \
    "--smart-case
--hidden
--glob=!.git/"
}

configure_bat() {
  local bat_config_path="${CONFIG_HOME}/bat/config"
  write_file_if_missing \
    "${bat_config_path}" \
    "bat config" \
    "--style=snip,numbers,changes,header
--theme=ansi"

  if command -v bat >/dev/null 2>&1; then
    bat cache --build >/dev/null 2>&1 || true
  fi
}

configure_bottom() {
  local bottom_config_path="${CONFIG_HOME}/bottom/bottom.toml"
  write_file_if_missing \
    "${bottom_config_path}" \
    "bottom config" \
    "[flags]
rate = 1000
process_command = true
group_processes = true
temperature_type = \"celsius\""
}

configure_delta() {
  local delta_config_path="${HOME}/.gitconfig.delta"
  local gitconfig_path="${HOME}/.gitconfig"

  write_file_if_missing \
    "${delta_config_path}" \
    "delta git config include file" \
    "[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    side-by-side = true
    line-numbers = true
    syntax-theme = Monokai Extended

[merge]
    conflictstyle = zdiff3"

  if [[ ! -f "${gitconfig_path}" ]]; then
    printf '%s\n' "[include]" "    path = ~/.gitconfig.delta" >"${gitconfig_path}"
    log "Created ${gitconfig_path} with delta include."
    return
  fi

  if ! rg -q 'path = ~/.gitconfig.delta' "${gitconfig_path}"; then
    printf '\n%s\n%s\n' "[include]" "    path = ~/.gitconfig.delta" >>"${gitconfig_path}"
    log "Added delta include to ${gitconfig_path}."
  else
    log "Delta include already present in ${gitconfig_path}."
  fi
}

configure_zellij() {
  link_file \
    "${REPO_DIR}/zellij/config.kdl" \
    "${CONFIG_HOME}/zellij/config.kdl" \
    "zellij config"
}

configure_zsh_aliases() {
  local zsh_tooling_path="${HOME}/.zshrc.rust-tools"
  local zshrc_path="${HOME}/.zshrc"
  local source_snippet="if [[ -f \$HOME/.zshrc.rust-tools ]]; then
  source \$HOME/.zshrc.rust-tools
fi"

  write_file_if_missing \
    "${zsh_tooling_path}" \
    "zsh rust-tools aliases" \
    "# Rust CLI tools defaults
export RIPGREP_CONFIG_PATH=\"${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config\"
alias ls='eza --group-directories-first --icons=auto'
alias ll='eza -lah --group-directories-first --icons=auto --git'
alias lt='eza --tree --level=2 --icons=auto'
alias top='btm'"

  if [[ ! -f "${zshrc_path}" ]]; then
    log "${zshrc_path} not found; skipping automatic sourcing of ${zsh_tooling_path}."
    return
  fi

  if ! rg -q '\.zshrc\.rust-tools' "${zshrc_path}"; then
    printf '\n%s\n' "${source_snippet}" >>"${zshrc_path}"
    log "Added rust-tools source snippet to ${zshrc_path}."
  else
    log "Rust-tools source snippet already present in ${zshrc_path}."
  fi
}

main() {
  parse_args "$@"

  if [[ "${INSTALL_BUILD_DEPS}" -eq 1 ]]; then
    install_build_deps
  else
    log "Skipping build dependency installation; assuming required system packages are already present."
  fi

  install_rust
  ensure_cargo_bin_in_path_or_shell_rcs
  install_rust_tools
  configure_ripgrep
  configure_bat
  configure_bottom
  configure_delta
  configure_zellij
  configure_zsh_aliases

  log "Rust CLI environment setup complete."
  log "Start a new shell (or run: source ~/.zshrc) to load aliases."
}

main "$@"
