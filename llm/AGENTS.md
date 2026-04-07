# Rules for LLM Agents

## Artifact output management

The goal here is do keep the agent generating artifacts separate from the main project to make version control easier.

- Save summaries of work in .agents/summaries/
- Save output like figures, tables, scripts in .agents/outputs/
- When applicable, use the .venv virtual env for the project, if not available, create one in .agents/.venv
