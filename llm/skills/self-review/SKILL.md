---
name: self-review
description: Build a local GitHub-style Files Changed preview and a hunk-complete defense report for a branch or working tree. Use for first-stage self-review before requesting human, PR, Bugbot, security, or multi-agent review.
---

# Self Review

Perform an adversarial first-stage review of the current change. Produce:

1. a local side-by-side Files Changed page; and
2. a Markdown defense report that accounts for every changed hunk.

The goal is to catch problems, not to justify the diff after the fact. If a
change has no sound reason, mark it for removal or correction.

## 1. Establish the review target

Identify:

- repository root and current branch;
- base ref and exact base commit;
- reviewed state: committed branch, index, working tree, and untracked files;
- whether a merge or rebase is in progress;
- original user goal and constraints.

Use the PR's actual base ref when known. Otherwise prefer the default branch of
an `upstream` remote, then `origin`. If more than one plausible base would
materially change the diff, ask the user. Never silently review against an
arbitrary ancestor.

Fetch the selected remote base before review when network access and credentials
permit; otherwise state that freshness was not verified. Record the fetch time,
resolved commit, and whether the base is an ancestor of `HEAD`.

For a normal branch, compare the merge base of `HEAD` and the selected base with
the current local snapshot, matching GitHub PR semantics while including local
changes. For an uncommitted merge of that base into a feature branch, compare
the base tree directly with the local snapshot so upstream changes do not
reappear as feature reversions. The builder's default `--comparison auto`
selects these modes and records the immutable comparison commit; override it
only with a documented reason.

Record the exact refs and commits in the report. State clearly when the local
preview differs from the remote PR because of uncommitted changes.

## 2. Build the local Files Changed preview

Run:

```bash
uv run --no-project python <skill-dir>/scripts/build_local_diff.py \
  --repo <repo-root> \
  --base <base-ref> \
  --output <artifact-dir>
```

Default `<artifact-dir>` to Git-private storage returned by
`git rev-parse --git-path self-review/<branch-slug>`. This avoids polluting the
reviewed working tree. Use a user-requested project path when provided.

The script creates:

- `files-changed.diff`: reproducible unified diff;
- `files-changed.html`: side-by-side GitHub-style preview;
- `hunk-manifest.md`: numbered file-change and textual-hunk inventory;
- `provenance.json`: committed, staged, unstaged, and untracked source layers;
- `metadata.json`: immutable refs, snapshot tree, status, and artifact hashes.

The builder snapshots tracked and untracked content into a temporary Git tree,
handles empty/binary/rename/mode changes, rejects unresolved index entries, and
fails if the tree changes during generation. Verify all files exist and the
manifest counts agree with metadata. `npx` may fetch the pinned
`diff2html-cli` renderer; report a renderer/network failure instead of claiming
the preview exists.

Open the HTML in Cursor when possible. If direct file rendering is not
available, serve the artifact directory:

```bash
uv run --no-project python <skill-dir>/scripts/build_local_diff.py \
  --serve <artifact-dir>
```

Run the server as a durable background command, read the printed URL, verify it
with an HTTP request, and give the user a clickable link. Do not claim the page
is visible until the URL responds.

## 3. Understand before defending

Read the complete diff and enough surrounding code to understand every hunk.
Inspect relevant callers, invariants, tests, documentation, and base behavior.
Use history or PR context when intent is not evident from code.
If submodules changed or are dirty, review each nested repository separately or
mark its contents explicitly out of scope; a gitlink alone is not a code review.

For each file-change ID (`C…`) and hunk ID (`H…`) in `hunk-manifest.md`,
classify it:

- required semantic change;
- safety/compatibility change;
- test or validation evidence;
- documentation or contract update;
- generated/mechanical change;
- incidental cleanup;
- unexplained or suspect.

Do not invent intent. An argument is defensible only when supported by the user
goal, code behavior, repository history, an invariant, or test evidence.

## 4. Perform the adversarial pass

Before writing the final defense, try to disprove it:

1. **Necessity:** Could the goal be met without this hunk?
2. **Correctness:** What inputs, states, or concurrency invalidate it?
3. **Compatibility:** What old behavior must remain unchanged?
4. **Scope:** Is this unrelated cleanup or accidental churn?
5. **Tests:** Does evidence exercise the changed behavior, or merely nearby code?
6. **Documentation:** Does the public contract match the implementation?
7. **Diff integrity:** Are generated, vendored, formatting-only, or conflict
   artifacts mixed into the feature?
8. **Operational risk:** Are migrations, rollout, fallback, observability, or
   performance implications missing?
9. **Negative space:** Which acceptance criteria or required behavior have no
   implementation or test change at all?

Act on findings:

- During an implementation task, fix clear defects within the authorized scope,
  rerun relevant validation, then regenerate all artifacts.
- During a review-only task, do not edit the reviewed code; report findings with
  file/hunk references and recommended remediation.
- Never rationalize an unnecessary hunk. Recommend removing it.
- Keep unresolved uncertainty explicit.

## 5. Write the defense report

Use [REPORT_TEMPLATE.md](REPORT_TEMPLATE.md). Save `defense-report.md` beside
the preview artifacts.

Every manifest change ID and hunk ID must appear exactly once in the report,
either directly or in a clearly enumerated grouped entry. Group only genuinely
inseparable changes, state why they are inseparable, and retain distinct
evidence/risk notes for every ID. Each entry must include:

- what changed;
- linkage to the goal and a necessity test;
- behavior intentionally changed or preserved;
- evidence;
- alternatives considered;
- disconfirming evidence, risk, or remaining uncertainty;
- verdict: keep, revise, remove, or unresolved.

Place one `<!-- self-review-id:C001 -->` or
`<!-- self-review-id:H001 -->` marker beside the ledger entry for each ID. After
drafting, run:

```bash
uv run --no-project python <skill-dir>/scripts/validate_report.py <artifact-dir>
```

Separate observed evidence from inference. Report tests actually run with exact
commands/results, environment, exit code, and the reviewed snapshot-tree/diff
hash. Check whether validation modified the tree and regenerate artifacts if it
did. Do not present expected CI coverage as completed validation.

## 6. Self-review the report

Run a second pass after drafting:

- run `validate_report.py` to reject missing, duplicate, and unknown IDs;
- challenge every “keep” verdict;
- search for repeated generic arguments that do not explain the actual hunk;
- verify claims against current code and logs;
- ensure findings are prominent, not buried in rationale;
- remove contradictions and stale counts;
- confirm regenerated artifacts represent the final reviewed tree.
- run unresolved-index checks and `git diff --check` before readiness.

When available, use a fresh review subagent for this adversarial pass, but
personally reconcile its findings rather than copying them uncritically.

The stage passes only when every hunk is accounted for and all blockers are
fixed or explicitly unresolved.

## 7. Handoff

Give the user:

- the clickable Files Changed preview;
- the defense report path;
- base and reviewed-state summary;
- blockers and high-risk unresolved items first;
- validation completed and validation still missing;
- confirmation of whether code was edited, committed, or pushed.

Then step through the review in this order:

1. blockers and questionable hunks;
2. production behavior and invariants;
3. tests and evidence;
4. documentation and operational impact;
5. mechanical or generated changes.

Do not commit, push, or mark the change review-ready without the user's approval.
