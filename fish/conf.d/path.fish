for dir in $HOME/.local/bin $HOME/.cargo/bin
  if not contains $dir $PATH
    set -gx PATH $dir $PATH
  end
end
