# AGENTS.md

Guidelines for AI agents working in this repository.

## Repository Overview

This is a **dotfiles** repo containing idempotent shell scripts that bootstrap a fresh Linux machine with zsh, Rust CLI tools, and sensible defaults. The main deliverables are `setup-zsh.sh` and `setup-rust-env.sh`.

## Dev Environment Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install pre-commit
pre-commit install
```

## Development Policies

### Pre-commit — always run before committing

This repo uses [pre-commit](https://pre-commit.com/). The full hook configuration lives in `.pre-commit-config.yaml`. Run hooks against all files before proposing changes:

```bash
pre-commit run --all-files
```

Active hooks:

| Hook | Purpose |
|---|---|
| `check-added-large-files` | Block accidentally committed binaries/blobs |
| `check-executables-have-shebangs` | Ensure scripts have proper shebangs |
| `check-yaml` | Validate YAML syntax |
| `end-of-file-fixer` | Ensure files end with a single newline |
| `trailing-whitespace` | Strip trailing whitespace |
| `detect-private-key` / `detect-secrets` | Prevent accidental secret leaks |
| `shellcheck` | Lint bash/sh scripts (`--severity=style`) |
| `shfmt` | Format bash/sh (2-space indent, `-ci`) |
| `beautysh` | Format zsh files (2-space indent) |
| `yamlfmt` | Format YAML files |
| `zsh-syntax-check` | Syntax-check zsh files via `zsh -n` |

If pre-commit modifies files (formatters like `shfmt`, `yamlfmt`, `beautysh`, `end-of-file-fixer`), stage the changes and retry the commit.

### Shell Script Conventions

- Start every bash script with `#!/usr/bin/env bash` and `set -euo pipefail`.
- Scripts must be **idempotent** — safe to re-run without side effects.
- Auto-detect the package manager (`apt`, `dnf`, `pacman`) rather than hard-coding one.
- Use `log()` helper functions for user-facing output (see existing scripts for the pattern).
- Indent with **2 spaces** (enforced by `shfmt`).

### YAML

- Formatting is enforced by `yamlfmt`. Do not manually adjust whitespace in YAML files — let the formatter handle it.

### Secrets

- Never commit credentials, tokens, or private keys. The `detect-secrets` and `detect-private-key` hooks will block this.
- Machine-specific or secret values belong in `~/.zshrc.local`, which is excluded from the repo.

### CI

GitHub Actions runs on push to `main` (see `.github/workflows/zsh_setup.yaml`). The workflow executes `setup-zsh.sh` on `ubuntu-latest` as a smoke test.

### Git

- Commit messages should be concise and describe **why**, not just what.
- Keep commits focused — one logical change per commit.
