#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
FISH_LOCAL_CONFIG="${CONFIG_HOME}/fish/config.local.fish"
CRUSH_CONFIG=""
CRUSH_VERSION=""
GO_VERSION="1.26.6"
SSH_PORT=""
IDENTITY_FILE=""
ASSUME_YES=0
DESTINATION=""
LOCAL_TEMP_DIR=""
REMOTE_TEMP_DIR=""
REMOTE_CONFIG_NAME=""
SSH_ARGS=()
SCP_ARGS=()

log() {
  printf '[%s] %s\n' "${SCRIPT_NAME}" "$*"
}

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options] [user@]hostname

Options:
  -p, --port PORT           SSH port
  -i, --identity FILE       SSH identity file
      --crush-config FILE   Local crushrc or crush.json
      --fish-config FILE    Local config.local.fish
      --crush-version VER   Crush version, such as v0.91.0
  -y, --yes                 Skip the confirmation prompt
  -h, --help                Show this help
EOF
}

cleanup() {
  if [[ -n "${LOCAL_TEMP_DIR}" && -d "${LOCAL_TEMP_DIR}" ]]; then
    rm -rf "${LOCAL_TEMP_DIR}"
  fi

  if [[ -n "${REMOTE_TEMP_DIR}" ]]; then
    "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${REMOTE_TEMP_DIR}" <<'REMOTE'
set -euo pipefail
rm -rf -- "$HOME/$1"
REMOTE
  fi
}

fail() {
  log "$*"
  exit 1
}

validate_safe_value() {
  local label="$1"
  local value="$2"

  if [[ "${value}" == *$'\n'* || "${value}" == *$'\r'* ]]; then
    fail "${label} contains a control character."
  fi
}

parse_args() {
  while (($#)); do
    case "$1" in
      -p | --port)
        (($# >= 2)) || fail "$1 requires a value."
        SSH_PORT="$2"
        shift 2
        ;;
      -i | --identity)
        (($# >= 2)) || fail "$1 requires a value."
        IDENTITY_FILE="$2"
        shift 2
        ;;
      --crush-config)
        (($# >= 2)) || fail "$1 requires a value."
        CRUSH_CONFIG="$2"
        shift 2
        ;;
      --fish-config)
        (($# >= 2)) || fail "$1 requires a value."
        FISH_LOCAL_CONFIG="$2"
        shift 2
        ;;
      --crush-version)
        (($# >= 2)) || fail "$1 requires a value."
        CRUSH_VERSION="$2"
        shift 2
        ;;
      -y | --yes)
        ASSUME_YES=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      --)
        shift
        (($# == 1)) || fail "Expected one SSH destination."
        DESTINATION="$1"
        shift
        ;;
      -*)
        fail "Unknown option: $1"
        ;;
      *)
        [[ -z "${DESTINATION}" ]] || fail "Expected one SSH destination."
        DESTINATION="$1"
        shift
        ;;
    esac
  done
}

resolve_inputs() {
  local command_path
  local local_version

  [[ -n "${DESTINATION}" ]] || {
    read -r -p "SSH destination ([user@]hostname): " DESTINATION
  }
  [[ -n "${DESTINATION}" ]] || fail "SSH destination is required."

  if [[ -z "${CRUSH_CONFIG}" ]]; then
    if [[ -f "${CONFIG_HOME}/crush/crushrc" ]]; then
      CRUSH_CONFIG="${CONFIG_HOME}/crush/crushrc"
    elif [[ -f "${CONFIG_HOME}/crush/crush.json" ]]; then
      CRUSH_CONFIG="${CONFIG_HOME}/crush/crush.json"
    else
      fail "No Crush config found at ${CONFIG_HOME}/crush/crushrc or ${CONFIG_HOME}/crush/crush.json."
    fi
  fi

  [[ -f "${CRUSH_CONFIG}" ]] || fail "Crush config is not a regular file: ${CRUSH_CONFIG}"
  [[ -f "${FISH_LOCAL_CONFIG}" ]] || fail "Fish local config is not a regular file: ${FISH_LOCAL_CONFIG}"

  REMOTE_CONFIG_NAME="$(basename "${CRUSH_CONFIG}")"
  [[ "${REMOTE_CONFIG_NAME}" == "crushrc" || "${REMOTE_CONFIG_NAME}" == "crush.json" ]] || fail "Crush config must be named crushrc or crush.json."

  if [[ -z "${CRUSH_VERSION}" ]]; then
    command_path="$(command -v crush || true)"
    [[ -n "${command_path}" ]] || fail "Crush is unavailable locally; pass --crush-version."
    local_version="$(crush --version)"
    CRUSH_VERSION="${local_version##* }"
  fi

  [[ "${CRUSH_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Crush version must look like v0.91.0."

  validate_safe_value "SSH destination" "${DESTINATION}"
  validate_safe_value "Crush config path" "${CRUSH_CONFIG}"
  validate_safe_value "Fish config path" "${FISH_LOCAL_CONFIG}"

  if [[ -n "${SSH_PORT}" ]]; then
    [[ "${SSH_PORT}" =~ ^[0-9]+$ ]] || fail "SSH port must be numeric."
    SSH_ARGS+=("-p" "${SSH_PORT}")
    SCP_ARGS+=("-P" "${SSH_PORT}")
  fi

  if [[ -n "${IDENTITY_FILE}" ]]; then
    [[ -f "${IDENTITY_FILE}" ]] || fail "SSH identity file is not a regular file: ${IDENTITY_FILE}"
    SSH_ARGS+=("-i" "${IDENTITY_FILE}")
    SCP_ARGS+=("-i" "${IDENTITY_FILE}")
  fi

  SSH_ARGS=(ssh "${SSH_ARGS[@]}")
  SCP_ARGS=(scp "${SCP_ARGS[@]}")
}

validate_local_setup() {
  local command_name
  local required_path
  local required_paths=(
    "setup-fish.sh"
    "install-llm-agents-helpers.sh"
    "llm/AGENTS.md"
    "fish/config.fish"
    "fish/conf.d/path.fish"
    "fish/conf.d/rust-tools.fish"
    "fish/conf.d/uv.fish"
    "fish/conf.d/setup-hooks.fish"
    "fish/fish_variables.tide"
    "fontconfig/50-terminal-nerd-font.conf"
  )

  for command_name in ssh scp tar; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "Required command not found: ${command_name}"
  done

  for required_path in "${required_paths[@]}"; do
    [[ -f "${SCRIPT_DIR}/${required_path}" ]] || fail "Required setup asset not found: ${SCRIPT_DIR}/${required_path}"
  done
}

check_remote() {
  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s <<'REMOTE'
set -euo pipefail
printf 'Connected to %s (%s).\n' "$(hostname)" "$(uname -m)"
[[ "$(uname -s)" == "Linux" ]] || {
  printf 'Remote operating system is not Linux.\n' >&2
  exit 1
}
[[ -w "$HOME" ]] || {
  printf 'Remote home is not writable: %s\n' "$HOME" >&2
  exit 1
}
command -v bash >/dev/null 2>&1 || {
  printf 'bash is required remotely.\n' >&2
  exit 1
}
if ! command -v curl >/dev/null 2>&1 && ! command -v git >/dev/null 2>&1; then
  printf 'Either curl or git is required remotely.\n' >&2
  exit 1
fi
REMOTE
}

confirm_setup() {
  local answer

  printf '\nRemote setup summary:\n'
  printf '  Destination: %s\n' "${DESTINATION}"
  printf '  Crush version: %s\n' "${CRUSH_VERSION}"
  printf '  Minimum Go version: %s\n' "${GO_VERSION}"
  printf '  Crush config: %s\n' "${CRUSH_CONFIG}"
  printf '  Fish local config: %s\n\n' "${FISH_LOCAL_CONFIG}"

  if ((ASSUME_YES)); then
    return
  fi

  read -r -p "Continue with remote changes? [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" || "${answer}" == "yes" || "${answer}" == "YES" ]] || fail "Cancelled."
}

run_fish_setup() {
  local remote_setup_dir=".local/share/dotfiles"

  LOCAL_TEMP_DIR="$(mktemp -d)"
  chmod 700 "${LOCAL_TEMP_DIR}"

  tar -C "${SCRIPT_DIR}" -czf "${LOCAL_TEMP_DIR}/fish-setup.tar.gz" \
    setup-fish.sh install-llm-agents-helpers.sh fish fontconfig/50-terminal-nerd-font.conf llm

  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${remote_setup_dir}" <<'REMOTE'
set -euo pipefail
mkdir -p -- "$HOME/$1"
chmod 700 -- "$HOME/$1"
REMOTE

  "${SCP_ARGS[@]}" "${LOCAL_TEMP_DIR}/fish-setup.tar.gz" "${DESTINATION}:${remote_setup_dir}/fish-setup.tar.gz"

  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${remote_setup_dir}" <<'REMOTE'
set -euo pipefail
cd "$HOME/$1"
tar -xzf fish-setup.tar.gz
rm -f fish-setup.tar.gz
bash setup-fish.sh
bash install-llm-agents-helpers.sh
REMOTE

  rm -rf "${LOCAL_TEMP_DIR}"
  LOCAL_TEMP_DIR=""
}

install_crush() {
  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${CRUSH_VERSION}" "${GO_VERSION}" <<'REMOTE'
set -euo pipefail
version="$1"
go_version="$2"
export PATH="$HOME/.local/bin:$HOME/.local/go/bin:$HOME/go/bin:$PATH"

if [[ -x "$HOME/.local/bin/crush" ]] && [[ "$("$HOME/.local/bin/crush" --version)" == *"$version" ]]; then
  printf 'Crush %s is already installed at %s.\n' "$version" "$HOME/.local/bin/crush"
  exit 0
fi

version_at_least() {
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

installed_go_version=""
if command -v go >/dev/null 2>&1; then
  installed_go_version="$(go version | sed -n 's/.* go\([0-9][^ ]*\).*/\1/p')"
fi

if [[ -z "$installed_go_version" ]] || ! version_at_least "$installed_go_version" "$go_version"; then
  case "$(uname -m)" in
    x86_64 | amd64) go_arch="amd64" ;;
    aarch64 | arm64) go_arch="arm64" ;;
    *)
      printf 'Unsupported architecture for rootless Go installation: %s\n' "$(uname -m)" >&2
      exit 1
      ;;
  esac

  command -v curl >/dev/null 2>&1 || {
    printf 'curl is required to install Go.\n' >&2
    exit 1
  }
  command -v sha256sum >/dev/null 2>&1 || {
    printf 'sha256sum is required to verify Go.\n' >&2
    exit 1
  }

  archive="go${go_version}.linux-${go_arch}.tar.gz"
  download_dir="$(mktemp -d)"
  trap 'rm -rf "$download_dir"' EXIT
  curl -fsSL "https://go.dev/dl/?mode=json&include=all" -o "$download_dir/releases.json"
  checksum="$(awk -v filename="$archive" '
    $0 ~ "\\\"filename\\\": \\\"" filename "\\\"" { found = 1 }
    found && /"sha256":/ {
      gsub(/[",]/, "", $2)
      print $2
      exit
    }
  ' "$download_dir/releases.json")"
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || {
    printf 'Could not resolve the official checksum for %s.\n' "$archive" >&2
    exit 1
  }
  curl -fL "https://go.dev/dl/$archive" -o "$download_dir/$archive"
  printf '%s  %s\n' "$checksum" "$download_dir/$archive" | sha256sum -c -

  rm -rf "$HOME/.local/go.new"
  mkdir -p "$HOME/.local/go.new" "$HOME/.local/bin"
  tar -xzf "$download_dir/$archive" -C "$HOME/.local/go.new" --strip-components=1
  rm -rf "$HOME/.local/go"
  mv "$HOME/.local/go.new" "$HOME/.local/go"
  ln -sfn "$HOME/.local/go/bin/go" "$HOME/.local/bin/go"
  ln -sfn "$HOME/.local/go/bin/gofmt" "$HOME/.local/bin/gofmt"
  export PATH="$HOME/.local/go/bin:$HOME/.local/bin:$PATH"
  printf 'Installed Go %s at %s.\n' "$go_version" "$HOME/.local/go"
fi

mkdir -p "$HOME/.local/bin"
GOBIN="$HOME/.local/bin" go install "github.com/charmbracelet/crush@$version"
"$HOME/.local/bin/crush" --version
REMOTE
}

copy_configs() {
  REMOTE_TEMP_DIR=".remote-crush-config.$(date -u +%Y%m%dT%H%M%SZ).$$"

  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${REMOTE_TEMP_DIR}" <<'REMOTE'
set -euo pipefail
umask 077
mkdir -p -- "$HOME/$1"
chmod 700 -- "$HOME/$1"
REMOTE

  "${SCP_ARGS[@]}" "${CRUSH_CONFIG}" "${DESTINATION}:${REMOTE_TEMP_DIR}/${REMOTE_CONFIG_NAME}"
  "${SCP_ARGS[@]}" "${FISH_LOCAL_CONFIG}" "${DESTINATION}:${REMOTE_TEMP_DIR}/config.local.fish"

  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${REMOTE_TEMP_DIR}" "${REMOTE_CONFIG_NAME}" <<'REMOTE'
set -euo pipefail
staging_dir="$HOME/$1"
config_name="$2"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
crush_dir="$config_home/crush"
fish_dir="$config_home/fish"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

umask 077
mkdir -p "$crush_dir" "$fish_dir"
chmod 700 "$crush_dir" "$fish_dir"

install_private_file() {
  source_path="$1"
  destination_path="$2"
  temporary_path="${destination_path}.new.$$"

  if [[ -e "$destination_path" ]]; then
    backup_path="${destination_path}.backup-${timestamp}"
    cp -p -- "$destination_path" "$backup_path"
    chmod 600 "$backup_path"
    printf 'Backup: %s\n' "$backup_path"
  fi

  install -m 600 -- "$source_path" "$temporary_path"
  mv -f -- "$temporary_path" "$destination_path"
}

install_private_file "$staging_dir/$config_name" "$crush_dir/$config_name"
install_private_file "$staging_dir/config.local.fish" "$fish_dir/config.local.fish"
rm -rf -- "$staging_dir"
REMOTE
  REMOTE_TEMP_DIR=""
}

verify_setup() {
  "${SSH_ARGS[@]}" "${DESTINATION}" bash -s -- "${REMOTE_CONFIG_NAME}" "${CRUSH_VERSION}" <<'REMOTE'
set -euo pipefail
config_name="$1"
expected_version="$2"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
crush_path="$config_home/crush/$config_name"
fish_path="$config_home/fish/config.local.fish"
crush_bin="$HOME/.local/bin/crush"

[[ -x "$crush_bin" ]]
[[ "$($crush_bin --version)" == *"$expected_version" ]]
[[ -f "$crush_path" && -f "$fish_path" ]]
[[ -L "$HOME/.agents/AGENTS.md" && -L "$HOME/.agents/skills" ]]
[[ "$(readlink -f "$HOME/.agents/AGENTS.md")" == "$HOME/.local/share/dotfiles/llm/AGENTS.md" ]]
[[ "$(readlink -f "$HOME/.agents/skills")" == "$HOME/.local/share/dotfiles/llm/skills" ]]
[[ "$(stat -c '%a' "$crush_path")" == "600" ]]
[[ "$(stat -c '%a' "$fish_path")" == "600" ]]

printf 'Remote host: %s\n' "$(hostname)"
printf 'Crush: %s (%s)\n' "$($crush_bin --version)" "$crush_bin"
printf 'Crush config: %s (600)\n' "$crush_path"
printf 'Fish local config: %s (600)\n' "$fish_path"
printf 'LLM helpers: %s\n' "$HOME/.agents"
REMOTE
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  resolve_inputs
  validate_local_setup
  check_remote
  confirm_setup
  run_fish_setup
  install_crush
  copy_configs
  verify_setup
  trap - EXIT
  log "Remote Crush setup complete."
}

main "$@"
