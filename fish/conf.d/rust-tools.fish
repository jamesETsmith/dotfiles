# Rust CLI tool integrations from setup-rust-env.sh.
# Only applied when the corresponding commands are on PATH.

if type -q rg; and test -f "$HOME/.config/ripgrep/config"
  set -q RIPGREP_CONFIG_PATH
  or set -gx RIPGREP_CONFIG_PATH "$HOME/.config/ripgrep/config"
end

if type -q eza
  alias ls 'eza --group-directories-first --icons=auto'
  alias ll 'eza -lah --group-directories-first --icons=auto --git'
  alias lt 'eza --tree --level=2 --icons=auto'
end

if type -q btm
  alias top btm
end
