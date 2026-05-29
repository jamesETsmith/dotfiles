if status is-interactive
  # Add user tool directories to PATH.
  fish_add_path -m $HOME/.local/bin $HOME/.cargo/bin
end
