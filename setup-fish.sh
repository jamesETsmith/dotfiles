#!/usr/bin/env bash
set -euo pipefail

# Installs Fish from source with cargo, then configures Fisher and Tide.
# Usage: ./setup-fish.sh

SCRIPT_NAME="$(basename "$0")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
FISH_CONFIG_DIR="${CONFIG_HOME}/fish"
RUSTUP_INIT_URL="https://sh.rustup.rs"
FISH_GIT_URL="https://github.com/fish-shell/fish-shell"
FISHER_INSTALL_URL="https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish"
TIDE_PLUGIN="ilancosman/tide@v6"
FONT_DIR="${HOME}/.local/share/fonts"
NERD_FONT_BASE_URL="https://github.com/romkatv/powerlevel10k-media/raw/master"
NERD_FONT_FILES=(
  "MesloLGS NF Regular.ttf"
  "MesloLGS NF Bold.ttf"
  "MesloLGS NF Italic.ttf"
  "MesloLGS NF Bold Italic.ttf"
)

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

install_build_deps() {
  local pkg_manager
  pkg_manager="$(detect_pkg_manager)"

  case "${pkg_manager}" in
    apt)
      log "Installing Fish build dependencies with apt..."
      sudo apt-get update
      sudo apt-get install -y curl git build-essential pkg-config cmake ca-certificates libpcre2-dev gettext
      ;;
    dnf)
      log "Installing Fish build dependencies with dnf..."
      sudo dnf install -y curl git gcc gcc-c++ make pkgconfig cmake ca-certificates
      ;;
    pacman)
      log "Installing Fish build dependencies with pacman..."
      sudo pacman -Syu --noconfirm curl git base-devel pkgconf cmake ca-certificates
      ;;
    *)
      log "No supported package manager detected (apt/dnf/pacman)."
      log "Install curl, git, cargo, and native build tools manually, then re-run ${SCRIPT_NAME}."
      ;;
  esac
}

install_runtime_deps() {
  local needed=()

  command -v curl >/dev/null 2>&1 || needed+=(curl)
  command -v git >/dev/null 2>&1 || needed+=(git)
  command -v fc-cache >/dev/null 2>&1 || needed+=(fontconfig)

  if [[ ${#needed[@]} -eq 0 ]]; then
    log "Fish runtime dependencies already installed."
    return
  fi

  local pkg_manager
  pkg_manager="$(detect_pkg_manager)"

  case "${pkg_manager}" in
    apt)
      log "Installing Fish runtime dependencies with apt..."
      sudo apt-get update
      sudo apt-get install -y "${needed[@]}" ca-certificates
      ;;
    dnf)
      log "Installing Fish runtime dependencies with dnf..."
      sudo dnf install -y "${needed[@]}" ca-certificates
      ;;
    pacman)
      log "Installing Fish runtime dependencies with pacman..."
      sudo pacman -S --needed --noconfirm "${needed[@]}" ca-certificates
      ;;
    *)
      log "No supported package manager detected (apt/dnf/pacman)."
      log "Install curl, git, and fontconfig manually, then re-run ${SCRIPT_NAME}."
      exit 1
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
    log "Installing rustup and stable Rust for cargo..."
    curl --proto '=https' --tlsv1.2 -fsSL "${RUSTUP_INIT_URL}" | sh -s -- -y --profile minimal --default-toolchain stable
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    log "cargo is still not available in PATH."
    exit 1
  fi
}

ensure_user_bin_dirs_in_path() {
  local dir
  for dir in "${HOME}/.local/bin" "${HOME}/.cargo/bin"; do
    if [[ "${dir}" == "${HOME}/.local/bin" ]]; then
      mkdir -p "${dir}"
    fi
    case ":${PATH}:" in
      *":${dir}:"*) ;;
      *)
        export PATH="${dir}:${PATH}"
        log "Added ${dir} to current PATH for this session."
        ;;
    esac
  done
}

install_fish() {
  local cargo_fish="${HOME}/.cargo/bin/fish"
  if [[ -x "${cargo_fish}" ]]; then
    log "fish already installed at ${cargo_fish}."
    return
  fi

  install_build_deps
  ensure_cargo_in_path
  ensure_user_bin_dirs_in_path

  log "Installing fish from ${FISH_GIT_URL} with cargo..."
  local temp_dir
  temp_dir="$(mktemp -d)"
  git clone --depth 1 "${FISH_GIT_URL}" "${temp_dir}"
  (
    cd "${temp_dir}"
    cargo install --path . --bin fish --no-default-features
  )
  rm -rf "${temp_dir}"
  ensure_user_bin_dirs_in_path
}

install_nerd_fonts() {
  local font_file
  local font_url
  local target_path
  local installed_any=0

  mkdir -p "${FONT_DIR}"

  for font_file in "${NERD_FONT_FILES[@]}"; do
    target_path="${FONT_DIR}/${font_file}"
    if [[ -f "${target_path}" ]]; then
      log "${font_file} already installed."
      continue
    fi

    font_url="${NERD_FONT_BASE_URL}/${font_file// /%20}"
    log "Installing ${font_file}..."
    curl -fL --connect-timeout 20 --max-time 120 -o "${target_path}" "${font_url}"
    installed_any=1
  done

  if [[ "${installed_any}" -eq 1 ]] && command -v fc-cache >/dev/null 2>&1; then
    log "Refreshing font cache..."
    fc-cache -f "${FONT_DIR}"
  fi
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

ensure_line_in_file() {
  local path="$1"
  local line="$2"

  mkdir -p "$(dirname "${path}")"
  touch "${path}"

  if ! grep -Fxq "${line}" "${path}"; then
    printf '%s\n' "${line}" >>"${path}"
    log "Added ${line} to ${path}."
  fi
}

write_fish_config() {
  link_file "${REPO_DIR}/fish/config.fish" "${FISH_CONFIG_DIR}/config.fish" "Fish config"
  link_file "${REPO_DIR}/fish/conf.d/path.fish" "${FISH_CONFIG_DIR}/conf.d/path.fish" "Fish PATH config"
  link_file "${REPO_DIR}/fish/conf.d/rust-tools.fish" "${FISH_CONFIG_DIR}/conf.d/rust-tools.fish" "Fish rust-tools config"

  ensure_line_in_file "${FISH_CONFIG_DIR}/fish_plugins" "jorgebucaran/fisher"
  ensure_line_in_file "${FISH_CONFIG_DIR}/fish_plugins" "${TIDE_PLUGIN}"
}

install_fisher_and_tide() {
  if fish -c "functions -q fisher; and functions -q tide" </dev/null; then
    log "Fisher and Tide already installed."
    return
  fi

  log "Installing Fisher and Tide..."
  fish -c "
    if not functions -q fisher
      curl -fsSL --connect-timeout 20 --max-time 120 ${FISHER_INSTALL_URL} | source
    end
    fisher install jorgebucaran/fisher ${TIDE_PLUGIN}
  " </dev/null
}

apply_tide_config() {
  local source_path="${REPO_DIR}/fish/fish_variables.tide"
  local target_path="${FISH_CONFIG_DIR}/fish_variables"

  mkdir -p "${FISH_CONFIG_DIR}"
  python3 - "${source_path}" "${target_path}" <<'PY'
from pathlib import Path
import sys

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])

tide_lines = [line for line in source_path.read_text(encoding="utf-8").splitlines() if line]
if target_path.exists():
    existing_lines = target_path.read_text(encoding="utf-8").splitlines()
else:
    existing_lines = [
        "# This file contains fish universal variable definitions.",
        "# VERSION: 3.0",
    ]

def is_tide_setting(line: str) -> bool:
    return (
        line.startswith("SETUVAR tide_")
        or line.startswith("SETUVAR _tide_left_items:")
        or line.startswith("SETUVAR _tide_right_items:")
    )

merged_lines = [line for line in existing_lines if not is_tide_setting(line)]
if merged_lines and merged_lines[-1] != "":
    merged_lines.append("")
merged_lines.extend(tide_lines)
merged_text = "\n".join(merged_lines) + "\n"

if target_path.exists() and target_path.read_text(encoding="utf-8") == merged_text:
    raise SystemExit(0)

target_path.write_text(merged_text, encoding="utf-8")
PY
  log "Applied Tide universal variable config to ${target_path}."
}

main() {
  install_runtime_deps
  ensure_user_bin_dirs_in_path
  install_fish
  install_nerd_fonts
  write_fish_config
  apply_tide_config
  install_fisher_and_tide
  apply_tide_config

  log "Fish setup complete."
}

main "$@"
