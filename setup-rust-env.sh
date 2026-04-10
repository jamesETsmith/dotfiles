#!/usr/bin/env bash
set -euo pipefail

# Installs Rust and common CLI tooling built with cargo.
# Usage: ./setup-rust-env.sh [--install-build-deps]

SCRIPT_NAME="$(basename "$0")"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
RUSTUP_INIT_URL="https://sh.rustup.rs"
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
  curl --proto '=https' --tlsv1.2 -fsSL "${RUSTUP_INIT_URL}" | sh -s -- -y --profile minimal --default-toolchain stable
  ensure_cargo_in_path
}

install_rust_tools() {
  local crate
  for crate in "${RUST_TOOLS[@]}"; do
    log "Installing ${crate}..."
    cargo install --locked "${crate}"
  done
}

ensure_cargo_bin_in_path_or_zshrc() {
  local cargo_bin="${HOME}/.cargo/bin"
  local zshrc_path="${HOME}/.zshrc"
  local cargo_path_snippet="export PATH=\"\$HOME/.cargo/bin:\$PATH\""

  if [[ ":${PATH}:" == *":${cargo_bin}:"* ]]; then
    log "cargo bin directory already present in current PATH."
  else
    export PATH="${cargo_bin}:${PATH}"
    log "Added ${cargo_bin} to current PATH for this session."
  fi

  if [[ ! -f "${zshrc_path}" ]]; then
    printf '%s\n' "${cargo_path_snippet}" >"${zshrc_path}"
    log "Created ${zshrc_path} with cargo PATH snippet."
    return
  fi

  if rg -q '(\.cargo/bin|\.cargo/env)' "${zshrc_path}"; then
    log "Cargo PATH setup already present in ${zshrc_path}."
    return
  fi

  printf '\n%s\n' "${cargo_path_snippet}" >>"${zshrc_path}"
  log "Added cargo PATH snippet to ${zshrc_path}."
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
  local zellij_config_path="${CONFIG_HOME}/zellij/config.kdl"
  write_file_if_missing \
    "${zellij_config_path}" \
    "zellij config" \
    'theme "default"
copy_command "xclip -selection clipboard"
scrollback_editor "vim"
default_layout "compact"'
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
  ensure_cargo_bin_in_path_or_zshrc
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
