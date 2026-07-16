# dotfiles

Setup scripts for bootstrapping a fresh Linux machine with zsh, Fish, Rust CLI tools, Vim, and sensible defaults.

## Quick Start (no clone required)

Run the scripts directly with `curl`. Each one is self-contained and idempotent.

### Zsh + Oh My Zsh + Starship

Installs zsh, [Oh My Zsh](https://ohmyz.sh/), autosuggestions/syntax-highlighting plugins, the [Starship](https://starship.rs/) prompt with the gruvbox-rainbow preset, and [uv](https://docs.astral.sh/uv/) for Python package management.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-zsh.sh | bash
```

### Rust CLI Environment

Installs Rust via [rustup](https://rustup.rs/) and a curated set of cargo tools: ripgrep, bat, eza, bottom, hyperfine, sd, tokei, git-delta, zellij, and Yazi. The script prefers prebuilt binaries through [cargo-binstall](https://github.com/cargo-bins/cargo-binstall), falls back to Cargo builds when needed, and verifies that each expected command is available. It also drops config files and shell aliases.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-rust-env.sh | bash
```

### Vim

Installs Vim, links the repo `.vimrc` to `~/.vimrc`, installs [vim-plug](https://github.com/junegunn/vim-plug), and installs the plugins declared in `.vimrc`.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-vim.sh | bash
```

### Fish + Tide

Installs the latest Fish release binary from GitHub (override with `FISH_VERSION=4.8.1` to pin), installs Hack Nerd Font Mono (and MesloLGS NF as fallback) for prompt and eza icons, installs [Fisher](https://github.com/jorgebucaran/fisher), installs [Tide](https://github.com/IlanCosman/tide), installs [uv](https://docs.astral.sh/uv/) for Python package management, and applies the Tide prompt config captured from this machine.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-fish.sh | bash
```

## Alternative: Clone and Run

```bash
git clone https://github.com/jamesETsmith/dotfiles.git
cd dotfiles
./setup-zsh.sh
./setup-rust-env.sh
./setup-vim.sh
./setup-fish.sh
```

## What Each Script Does

| Script              | Highlights                                                                                                                                     |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup-zsh.sh`      | Installs zsh, Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, Starship prompt, uv, writes `.zshrc`, sets zsh as default shell         |
| `setup-rust-env.sh` | Installs build deps, Rust toolchain, ripgrep, bat, eza, bottom, hyperfine, sd, tokei, git-delta, zellij, yazi-build, writes tool configs and shell aliases |
| `setup-vim.sh`      | Installs Vim, links `.vimrc`, installs vim-plug, and installs Vim plugins declared in `.vimrc`                                                  |
| `setup-fish.sh`     | Installs latest Fish from GitHub release binaries, installs Hack Nerd Font Mono + MesloLGS NF, installs Fisher and Tide, installs uv, links Fish config, and applies saved Tide prompt settings               |

These scripts auto-detect your package manager (apt, dnf, or pacman) and are safe to re-run.

## CI Timing

GitHub Actions wraps setup and verification steps with `ci/measure-step.sh`. Each run writes timing details to the job summary and uploads a `timings.jsonl` artifact named by workflow and commit SHA, making setup-time changes easy to compare across commits.

## License

[MIT](LICENSE)
