# Refresh an interactive fish session after setup-fish.sh updates config.
function __dotfiles_reload_after_setup --on-event fish_prompt
    set -l marker "$__fish_config_dir/.dotfiles-setup-reload"
    test -f $marker || return

    rm -f $marker
    functions -e __dotfiles_reload_after_setup

    # exec fish reloads fish_variables from disk and re-initializes Tide.
    exec fish
end
