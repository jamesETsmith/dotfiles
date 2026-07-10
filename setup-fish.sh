#!/usr/bin/env bash
set -euo pipefail

# Installs Fish from source with cargo, then configures Fisher and Tide.
# Usage: ./setup-fish.sh

SCRIPT_NAME="$(basename "$0")"
DOTFILES_GIT_URL="https://github.com/jamesETsmith/dotfiles.git"
DOTFILES_BRANCH="main"
DOTFILES_CACHE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles"
# BASH_SOURCE[0] is unset when the script is piped into bash (curl | bash).
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
if [[ -n "${SCRIPT_PATH}" && -f "${SCRIPT_PATH}" ]]; then
  SCRIPT_PATH="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)/$(basename "${SCRIPT_PATH}")"
else
  SCRIPT_PATH=""
fi
REPO_DIR=""
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

fish_config_files_present() {
  local repo_dir="$1"
  local relative_path
  local required_files=(
    "fish/config.fish"
    "fish/conf.d/path.fish"
    "fish/conf.d/rust-tools.fish"
    "fish/conf.d/uv.fish"
    "fish/conf.d/setup-hooks.fish"
    "fish/fish_variables.tide"
  )

  for relative_path in "${required_files[@]}"; do
    if [[ ! -f "${repo_dir}/${relative_path}" ]]; then
      return 1
    fi
  done
}

resolve_repo_dir() {
  local candidate_dir

  if [[ -n "${SCRIPT_PATH}" ]]; then
    candidate_dir="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
    if fish_config_files_present "${candidate_dir}"; then
      REPO_DIR="${candidate_dir}"
      return
    fi
  fi

  if fish_config_files_present "${DOTFILES_CACHE_DIR}"; then
    REPO_DIR="${DOTFILES_CACHE_DIR}"
    return
  fi

  log "Fetching dotfiles repo for Fish config..."
  if [[ -d "${DOTFILES_CACHE_DIR}/.git" ]]; then
    git -C "${DOTFILES_CACHE_DIR}" fetch --depth 1 origin "${DOTFILES_BRANCH}"
    git -C "${DOTFILES_CACHE_DIR}" checkout "${DOTFILES_BRANCH}"
    git -C "${DOTFILES_CACHE_DIR}" reset --hard "origin/${DOTFILES_BRANCH}"
  else
    mkdir -p "$(dirname "${DOTFILES_CACHE_DIR}")"
    git clone --depth 1 --branch "${DOTFILES_BRANCH}" "${DOTFILES_GIT_URL}" "${DOTFILES_CACHE_DIR}"
  fi

  if ! fish_config_files_present "${DOTFILES_CACHE_DIR}"; then
    log "Fish config files missing after fetching dotfiles repo."
    exit 1
  fi

  REPO_DIR="${DOTFILES_CACHE_DIR}"
}

ensure_repo_dir() {
  if [[ -z "${REPO_DIR}" ]] || ! fish_config_files_present "${REPO_DIR}"; then
    log "Dotfiles repo directory is not configured."
    exit 1
  fi
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
  if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "${HOME}/.cargo/env"
  fi

  if command -v cargo >/dev/null 2>&1 && cargo --version >/dev/null 2>&1; then
    return
  fi

  if command -v rustup >/dev/null 2>&1; then
    log "Repairing rustup stable toolchain for cargo..."
    rustup default stable
    if cargo --version >/dev/null 2>&1; then
      return
    fi
  fi

  log "Installing rustup and stable Rust for cargo..."
  ensure_executable_tmpdir
  curl --proto '=https' --tlsv1.2 -fsSL "${RUSTUP_INIT_URL}" | sh -s -- -y --profile minimal --default-toolchain stable
  # shellcheck disable=SC1091
  source "${HOME}/.cargo/env"

  if ! cargo --version >/dev/null 2>&1; then
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
  ensure_executable_tmpdir
  ensure_executable_cargo_target_dir
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

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    log "uv already installed."
    return
  fi

  log "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
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
  local had_link=0

  mkdir -p "$(dirname "${target_path}")"

  if [[ -L "${target_path}" ]]; then
    had_link=1
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

  if [[ "${target_path}" == *"/conf.d/setup-hooks.fish" && "${had_link}" -eq 0 ]]; then
    SETUP_HOOKS_NEWLY_LINKED=1
  fi
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
  SETUP_HOOKS_NEWLY_LINKED=0

  link_file "${REPO_DIR}/fish/config.fish" "${FISH_CONFIG_DIR}/config.fish" "Fish config"
  link_file "${REPO_DIR}/fish/conf.d/path.fish" "${FISH_CONFIG_DIR}/conf.d/path.fish" "Fish PATH config"
  link_file "${REPO_DIR}/fish/conf.d/rust-tools.fish" "${FISH_CONFIG_DIR}/conf.d/rust-tools.fish" "Fish rust-tools config"
  link_file "${REPO_DIR}/fish/conf.d/uv.fish" "${FISH_CONFIG_DIR}/conf.d/uv.fish" "Fish uv config"
  link_file "${REPO_DIR}/fish/conf.d/setup-hooks.fish" "${FISH_CONFIG_DIR}/conf.d/setup-hooks.fish" "Fish setup hooks"

  ensure_line_in_file "${FISH_CONFIG_DIR}/fish_plugins" "jorgebucaran/fisher"
  ensure_line_in_file "${FISH_CONFIG_DIR}/fish_plugins" "${TIDE_PLUGIN}"
}

install_fisher_and_tide() {
  FISHER_TIDE_INSTALLED=0

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
  FISHER_TIDE_INSTALLED=1
}

is_interactive_fish_parent() {
  [[ -t 1 ]] || return 1
  local parent_comm
  parent_comm="$(ps -o comm= -p "${PPID}" 2>/dev/null | tr -d ' ')"
  [[ "${parent_comm}" == *fish* ]]
}

queue_fish_session_refresh() {
  mkdir -p "${FISH_CONFIG_DIR}"
  : >"${FISH_CONFIG_DIR}/.dotfiles-setup-reload"

  if is_interactive_fish_parent; then
    log "Will refresh this fish session when setup finishes."
    if [[ "${SETUP_HOOKS_NEWLY_LINKED:-0}" -eq 1 ]]; then
      log "Setup hooks were just installed; run: exec fish"
    fi
  else
    log "Start a new fish session (or run: exec fish) to load prompt changes."
  fi
}

reload_tide_prompt() {
  if ! fish -c "functions -q tide" </dev/null 2>&1; then
    log "Tide not installed; skipping prompt reload."
    return
  fi

  if [[ "${TIDE_CONFIG_CHANGED:-}" == "1" || "${FISHER_TIDE_INSTALLED:-0}" -eq 1 ]]; then
    queue_fish_session_refresh
  fi
}

apply_tide_config() {
  local source_path="${REPO_DIR}/fish/fish_variables.tide"
  local target_path="${FISH_CONFIG_DIR}/fish_variables"

  if [[ ! -f "${source_path}" ]]; then
    log "Tide config source not found at ${source_path}."
    exit 1
  fi

  mkdir -p "${FISH_CONFIG_DIR}"
  TIDE_CONFIG_CHANGED="$(
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
        or line.startswith("SETUVAR _tide_prompt_")
    )

merged_lines = [line for line in existing_lines if not is_tide_setting(line)]
if merged_lines and merged_lines[-1] != "":
    merged_lines.append("")
merged_lines.extend(tide_lines)
merged_text = "\n".join(merged_lines) + "\n"

if target_path.exists() and target_path.read_text(encoding="utf-8") == merged_text:
    print("0")
else:
    target_path.write_text(merged_text, encoding="utf-8")
    print("1")
PY
  )"

  if [[ "${TIDE_CONFIG_CHANGED}" == "1" ]]; then
    log "Applied Tide universal variable config to ${target_path}."
  else
    log "Tide universal variable config already up to date at ${target_path}."
    TIDE_CONFIG_CHANGED=""
  fi
}

configure_bashrc() {
  local bashrc_path="${HOME}/.bashrc"
  local bashrc_changed

  mkdir -p "$(dirname "${bashrc_path}")"
  touch "${bashrc_path}"

  bashrc_changed="$(
    python3 - "${bashrc_path}" "${SCRIPT_NAME}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
script_name = sys.argv[2]
start_marker = "# >>> dotfiles fish setup >>>"
end_marker = "# <<< dotfiles fish setup <<<"
block_lines = [
    start_marker,
    f"# Added by {script_name}: start fish for interactive bash sessions.",
    "if [[ $- == *i* ]] && command -v fish >/dev/null 2>&1; then",
    "  exec fish",
    "fi",
    end_marker,
]
block = "\n".join(block_lines) + "\n"

existing_text = path.read_text(encoding="utf-8") if path.exists() else ""
lines = existing_text.splitlines(keepends=True)
filtered_lines = []
in_block = False

for line in lines:
    stripped = line.rstrip("\n")
    if stripped == start_marker:
        in_block = True
        continue
    if stripped == end_marker:
        in_block = False
        continue
    if not in_block:
        filtered_lines.append(line)

base_text = "".join(filtered_lines).rstrip("\n")
if base_text:
    merged_text = base_text + "\n\n" + block
else:
    merged_text = block

if existing_text == merged_text:
    print("0")
else:
    path.write_text(merged_text, encoding="utf-8")
    print("1")
PY
  )"

  if [[ "${bashrc_changed}" == "1" ]]; then
    log "Added fish startup block to ${bashrc_path}."
  else
    log "Fish startup block already up to date in ${bashrc_path}."
  fi
}

main() {
  resolve_repo_dir
  ensure_repo_dir
  install_runtime_deps
  ensure_user_bin_dirs_in_path
  install_fish
  install_nerd_fonts
  install_uv
  write_fish_config
  install_fisher_and_tide
  apply_tide_config
  reload_tide_prompt
  configure_bashrc

  log "Fish setup complete."
}

main "$@"
