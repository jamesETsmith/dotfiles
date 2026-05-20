---
name: session-skill-miner
description: Use when the user asks to audit past Crush sessions for recurring workflows that should become reusable skills — runs a manual, incremental review over `~/.crush/crush.db` since the last audit and proposes new skills.
---

# Session Skill Miner

## Description

A manually-triggered audit that helps agents (and the user) learn new
skills from prior Crush sessions. It reads the local Crush SQLite
database (`~/.crush/crush.db`, read-only), pulls every session newer
than the last audit, and looks for **recurring workflows** —
sequences of tool calls and user prompts that show up across multiple
sessions. Anything that recurs is a candidate for a new skill.

This skill writes only two things:

1. A timestamp file marking when the audit ran (so the next audit is incremental).
2. A markdown audit report under `.agents/summaries/session-skill-miner/`.

It does **not** create new skills on its own — proposals require the
user's explicit approval before scaffolding anything under
`~/.agents/skills/`.

## When to Use

- The user says "audit my sessions", "mine my history for skills", "look for patterns in my Crush sessions", or similar.
- After a stretch of work where the user noticed themselves repeating instructions to the agent.
- **Do not** run automatically. This is opt-in only.

## Inputs and outputs

| Artifact | Path | Direction |
|---|---|---|
| Crush session DB | `~/.crush/crush.db` | read-only |
| Last-audit timestamp | `~/.agents/state/session-skill-miner/last_audit` | read+write |
| Audit report | `.agents/summaries/session-skill-miner/YYYY-MM-DD-audit.md` | write |
| New skill scaffolds | `~/.agents/skills/<skill-name>/SKILL.md` | write — only after user approves |

The helper script lives next to this file at
`scripts/extract_sessions.py` and is the only thing that touches the DB.

## Process

### 1. Pull session digests since the last audit

```bash
SKILL_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"   # or the dir containing this SKILL.md
python3 "$SKILL_DIR/scripts/extract_sessions.py" --min-messages 4 > /tmp/session-audit.jsonl
```

Useful flags:

| Flag | Effect |
|---|---|
| `--since 0` | Force a full re-scan of every session in the DB (ignore stored last-audit timestamp). |
| `--since <epoch_s>` | Audit only sessions whose `updated_at` is newer than this many seconds since the Unix epoch. |
| `--min-messages N` | Skip sessions shorter than `N` messages (default `4`). Trivial sessions rarely reveal workflows. |
| `--include-current` | Include the in-progress session. Off by default so the audit doesn't analyze itself. |
| `--mark` | After the audit completes, update the last-audit timestamp. **Only pass this once the user has accepted/rejected the proposals** — otherwise re-runs would silently skip the same sessions. |

Each non-meta line of the output is a JSON object with the session
title, user prompts (truncated), and the ordered tool-call sequence
(tool name + one-line summary). The last line is a `_meta` summary
including `session_count`.

### 2. Cluster recurring workflows

Read every digest and look for patterns that show up across **two or
more sessions**. Heuristics:

- **Repeated tool-call sequences.** e.g. `bash(slurm) → bash(slurm) → bash(slurm)` across multiple SLURM debugging sessions suggests a `slurm-debug` skill.
- **Recurring prompt verbs/nouns.** Cluster user prompts by domain (SLURM, GPUs, git, dotfiles, benchmarking, model API debugging, etc.). A noun that appears in 3+ sessions is a strong signal.
- **Repeated corrections.** If the user repeatedly says "no, do X instead", whatever X is may belong in a skill or AGENTS.md.
- **Long sessions on the same topic.** A 30-message session and a 25-message session both about the same domain → almost certainly skill-worthy.
- **Cross-model repetition.** The same workflow appearing under Sonnet, GPT, and Gemini sessions is stronger evidence than one model alone.

Ignore one-off sessions, trivial sessions (already filtered by `--min-messages`), and meta-sessions about Crush itself unless they recur.

### 3. Write the audit report

Save to `.agents/summaries/session-skill-miner/YYYY-MM-DD-audit.md`
(create the directory if missing). Suggested structure:

```markdown
# Session audit — <date>

- Window: `<since_s>` → `<now_s>` (`N` sessions reviewed)
- DB: `~/.crush/crush.db`

## Proposed skills

### `<kebab-case-name>`
- **Trigger description (for SKILL.md frontmatter):** <one sentence>
- **Evidence:** N sessions, e.g.
  - `<session-id-prefix>` — "<title>" — <why it fits>
- **Core workflow:** <2–5 bullet outline of the steps the skill should encode>
- **Open questions for the user:** <anything ambiguous>

### `<next proposal>`
…

## Not proposing (but noted)
- <pattern that recurred but didn't meet the bar, with one-line reason>

## Stats
- Sessions reviewed: N
- Sessions skipped (current): yes/no
- Most-used tools across the window: bash (X), view (Y), grep (Z), …
```

Keep proposals **specific** — "git workflow skill" is too vague; "slurm-reservation-lookup" is good.

### 4. Present and wait for approval

Show the user the proposal list (file path + one-line summary per
proposal). **Do not scaffold skills yet.** Ask which proposals to
accept; offer "all", "none", or a subset.

### 5. Scaffold accepted skills (only on approval)

For each accepted proposal, create
`~/.agents/skills/<name>/SKILL.md` using the existing skill files
under `~/.agents/skills/` as templates. Match the existing frontmatter
(`name`, `description`) and section style (Description, When to Use,
Process / Instructions). If the skill needs scripts, put them under
`~/.agents/skills/<name>/scripts/` and reference them by path
relative to the SKILL.md.

### 6. Mark the audit complete

Only after step 5 (or after the user explicitly says "skip all"):

```bash
python3 "$SKILL_DIR/scripts/extract_sessions.py" --mark --since 0 --min-messages 999999 >/dev/null
# `--mark` updates the timestamp only when at least one session was emitted,
# so the line above is a no-op on a fresh DB. Prefer to re-run the original
# audit command with `--mark` appended:
python3 "$SKILL_DIR/scripts/extract_sessions.py" --mark --min-messages 4 > /dev/null
```

## Rules

1. **Read-only DB access.** Only the helper script may touch `~/.crush/crush.db`, and it opens the connection in `mode=ro`. Never write to it.
2. **Never auto-create skills.** Proposals always require explicit user approval before scaffolding.
3. **Exclude the current session by default.** Avoid the recursive case where the audit's own session pollutes the next audit.
4. **Be conservative.** A pattern needs at least two distinct sessions before being proposed. One-offs go in the "Not proposing" section.
5. **Respect privacy.** The audit report can quote short snippets of prompts but should not dump full transcripts.
6. **Mark only after wrap-up.** `--mark` runs last, after the user has decided what to accept. If the user defers a decision, do not mark.

## Troubleshooting

- **`error: database not found`** — the user hasn't enabled persistent session storage. Check `options.data_directory` in their `crush.json` (should resolve to a directory containing `crush.db`).
- **Zero sessions emitted** — likely because the last-audit timestamp is recent. Re-run with `--since 0` for a full sweep, or pick an explicit epoch-second value.
- **The script reports timestamps as seconds, but the schema says ms.** Crush's column comments are wrong; the values are seconds. The script already accounts for this.
