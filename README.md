# dotfiles

Setup scripts for bootstrapping a fresh Linux machine with zsh, Rust CLI tools, and sensible defaults.

## Quick Start (no clone required)

Run the scripts directly with `curl`. Each one is self-contained and idempotent.

### Zsh + Oh My Zsh + Starship

Installs zsh, [Oh My Zsh](https://ohmyz.sh/), autosuggestions/syntax-highlighting plugins, the [Starship](https://starship.rs/) prompt with the gruvbox-rainbow preset, and [uv](https://docs.astral.sh/uv/) for Python package management.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-zsh.sh | bash
```

### Rust CLI Environment

Installs Rust via [rustup](https://rustup.rs/) and a curated set of cargo tools: ripgrep, bat, eza, bottom, hyperfine, sd, tokei, git-delta, zellij, and yazi-build. Also drops config files and shell aliases.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-rust-env.sh | bash
```

## Alternative: Clone and Run

```bash
git clone https://github.com/jamesETsmith/dotfiles.git
cd dotfiles
./setup-zsh.sh
./setup-rust-env.sh
```

## What Each Script Does

| Script              | Highlights                                                                                                                                     |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup-zsh.sh`      | Installs zsh, Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, Starship prompt, uv, writes `.zshrc`, sets zsh as default shell         |
| `setup-rust-env.sh` | Installs build deps, Rust toolchain, ripgrep, bat, eza, bottom, hyperfine, sd, tokei, git-delta, zellij, yazi-build, writes tool configs and shell aliases |

Both scripts auto-detect your package manager (apt, dnf, or pacman) and are safe to re-run.

## CI Timing

GitHub Actions wraps setup and verification steps with `ci/measure-step.sh`. Each run writes timing details to the job summary and uploads a `timings.jsonl` artifact named by workflow and commit SHA, making setup-time changes easy to compare across commits.

## License

[MIT](LICENSE)
