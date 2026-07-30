if status is-interactive
  # Add user tool directories to PATH.
  fish_add_path -m $HOME/.local/bin $HOME/.cargo/bin
end

function daily
  if test (count $argv) -eq 0
    echo "Usage: daily <name>" >&2
    return 2
  end

  mkdir -- (date +%Y_%m_%d)_(string join _ $argv)
end

# Put machine-specific or secret values in ~/.config/fish/config.local.fish
if test -f $HOME/.config/fish/config.local.fish
  source $HOME/.config/fish/config.local.fish
end
