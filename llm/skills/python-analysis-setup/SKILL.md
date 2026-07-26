---
name: python-analysis-setup
description: Use when setting up a Python environment for data analysis, including reproducible dependencies with uv, matplotlib, seaborn presentation styling, ruff, ty, and pytest.
user-invocable: true
---

# Python Analysis Setup

## Purpose

Set up a reproducible Python environment for data analysis. Use `uv` exclusively for Python version selection, virtual environments, dependency installation, locking, and command execution. The default analysis stack is Matplotlib and Seaborn, with Seaborn configured for presentation-quality plots.

## When to Use

- Starting a new Python analysis, notebook, visualization, or report.
- Adding a reproducible analysis environment to an existing repository.
- Standardizing plotting, linting, type checking, and testing for Python analysis code.

## Required Stack

- Dependency and environment management: `uv`
- Plotting: `matplotlib`, `seaborn`
- Linting and formatting: `ruff`
- Type checking: `ty`
- Tests: `pytest`

Do not use `pip`, `venv`, Poetry, Conda, or other dependency managers for project dependencies. Do not create or modify a `requirements.txt`; use `pyproject.toml` and `uv.lock`.

## Setup Procedure

1. Inspect the repository before changing files. Reuse an existing `pyproject.toml`, `uv.lock`, and project layout where present.
2. For a new project, initialize it with `uv init`. For an existing project without package metadata, create a standards-compliant `pyproject.toml` using `uv init` or `uv add`.
3. Add the required runtime dependencies:

   ```bash
   uv add matplotlib seaborn
   ```

4. Add the development dependencies:

   ```bash
   uv add --dev ruff ty pytest
   ```

5. Ensure the project declares a supported Python version in `requires-python`. Prefer the current stable Python release supported by the project and its dependencies; do not change an existing compatible constraint without a reason.
6. Commit the resolved dependency graph to `uv.lock`. Do not manually edit the lock file.
7. Install or synchronize the environment with:

   ```bash
   uv sync
   ```

8. Run tools through `uv run`, never by depending on globally installed project tools:

   ```bash
   uv run ruff check .
   uv run ruff format --check .
   uv run ty check
   uv run pytest
   ```

## Plotting Defaults

Every analysis that uses Seaborn must apply the presentation context before plotting. Put this near imports or in a shared plotting module, before figures are constructed:

```python
import seaborn as sns

sns.set_theme(context="talk", style="whitegrid")
```

- `context="talk"` is the required default for presentation-quality sizing.
- Use `style="whitegrid"` unless the analysis needs a different style for clarity.
- Make exceptions only when a specific output format requires them, and keep the exception local to that plot or module.
- Use explicit labels, units, legends, accessible color choices, and `tight_layout()` or constrained layout so plots remain readable when embedded in slides or reports.

## Project Configuration

Keep tool configuration in `pyproject.toml`. Add only settings that serve a project need and preserve existing choices. For a new project, use these minimal defaults:

```toml
[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "UP"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

Prefer a `src/` layout for installable packages. For one-off analyses, place reusable code in a named package or module and notebooks in `notebooks/`; do not put generated figures, caches, or large data files under source control unless the project explicitly requires it.

## Verification

After setup or dependency changes:

1. Run `uv lock --check` to confirm the lock file matches project metadata.
2. Run `uv sync --locked` to confirm a clean reproducible installation.
3. Run Ruff linting and format checks, Ty type checks, and Pytest.
4. For code that produces plots, run a lightweight plotting smoke test and confirm Seaborn's active context is `talk`.
5. Report the Python version, `uv` commands run, dependency changes, tool results, and any unavailable checks.
