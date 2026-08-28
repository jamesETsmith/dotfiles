# Rules for LLM Agents

## Artifact output management

The goal here is do keep the agent generating artifacts separate from the main project to make version control easier.

- Save summaries of work in .agents/summaries/
- Save output like figures, tables, scripts in .agents/outputs/
- When applicable, use the .venv virtual env for the project, if not available, create one in .agents/.venv
- If working in a git project, track your work in a feature branch. Wait for explicit approval before merging it back.

## Structural code search

- Use `ast-grep` (`sg`) for syntax-aware code searches and transformations when language structure matters.
- Prefer `ast-grep` over text search for locating definitions, calls, imports, or other syntax patterns, and for refactors that should avoid comments and string literals.
- Use text search for plain text, configuration, documentation, or initial discovery when the code structure is unknown.
- Preview matches before applying rewrites, then run the relevant tests and formatters.
