# dotfiles

Setup scripts for bootstrapping a fresh Linux machine with zsh, Rust CLI tools, and sensible defaults.

## Quick Start (no clone required)

Run the scripts directly with `curl`. Each one is self-contained and idempotent.

### Zsh + Oh My Zsh + Starship

Installs zsh, [Oh My Zsh](https://ohmyz.sh/), autosuggestions/syntax-highlighting plugins, and the [Starship](https://starship.rs/) prompt with the gruvbox-rainbow preset.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-zsh.sh | bash
```

### Rust CLI Environment

Installs Rust via [rustup](https://rustup.rs/) and a curated set of cargo tools: ripgrep, bat, eza, bottom, hyperfine, sd, tokei, and git-delta. Also drops config files and shell aliases.

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-rust-env.sh | bash
```

### Both at Once

```bash
curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-zsh.sh | bash \
  && curl -fsSL https://raw.githubusercontent.com/jamesETsmith/dotfiles/main/setup-rust-env.sh | bash
```

> **Tip:** Run the zsh script first so that `.zshrc` exists before the Rust script appends its PATH and alias snippets.

## Alternative: Clone and Run

```bash
git clone https://github.com/jamesETsmith/dotfiles.git
cd dotfiles
./setup-zsh.sh
./setup-rust-env.sh
```

## What Each Script Does

| Script | Highlights |
|---|---|
| `setup-zsh.sh` | Installs zsh, Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, Starship prompt, writes `.zshrc`, sets zsh as default shell |
| `setup-rust-env.sh` | Installs build deps, Rust toolchain, ripgrep, bat, eza, bottom, hyperfine, sd, tokei, git-delta, writes tool configs and shell aliases |

Both scripts auto-detect your package manager (apt, dnf, or pacman) and are safe to re-run.

## License

[MIT](LICENSE)
