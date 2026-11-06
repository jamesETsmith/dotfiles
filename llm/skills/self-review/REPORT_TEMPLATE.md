# Self-review defense report

## Review identity

- Repository:
- Branch:
- Base ref and commit:
- Base fetch/freshness and ancestry:
- Comparison mode and immutable comparison commit:
- Snapshot tree and diff hash:
- Reviewed state:
- Merge/rebase state:
- Original goal:
- Diff summary:
- Generated artifacts:

## Executive verdict

State whether the change is ready for human review. Lead with blockers,
questionable changes, and unsupported claims.

## Behavioral invariants

List the properties that must hold before and after the change.

## Acceptance-criteria coverage

Map every requested behavior to implementation IDs and validation. Explicitly
list requested behavior missing from the diff.

## Findings

### Blockers

- Finding, evidence, affected hunk IDs, and remediation.

### Risks and open questions

- Risk, evidence, affected hunk IDs, and next validation.

### Candidate removals

- Unnecessary, incidental, duplicate, formatting-only, or unexplained changes.

## Hunk defense ledger

Account for every file-change ID (`C…`) and textual-hunk ID (`H…`). Use one
entry per ID, or an explicitly enumerated group of genuinely inseparable IDs.
State why any group is inseparable and retain distinct evidence/risk per ID.

`render_review.py` shows each entry as a card beside its hunks, so keep this
structure:

- Keep this section's heading exactly `## Hunk defense ledger`. The ledger
  runs until the next `##` heading.
- Start each entry with a `###` heading and put its ID markers below the
  heading. An entry with no markers gets no card.
- Do not use `####` or deeper headings inside the ledger.
- End each entry with `**Verdict:**` and exactly one of Keep, Revise, Remove,
  or Unresolved. The card color comes from that word.
- The leading `[IDs]` is removed from the card title, because the cards already
  show the IDs as badges. Keep the rest of the title to a path, line range,
  and a short name.
- The notes column is narrow. Use short bullets, and put wide tables and long
  code blocks in another section, then refer to them from the entry.

### `[C001, H001] path: new-line-range` — short change name
<!-- self-review-id:C001 -->
<!-- self-review-id:H001 -->

- **What changed:**
- **Goal linkage / necessity test:**
- **Behavior changed or preserved:**
- **Evidence:**
- **Alternative considered:**
- **Disconfirming evidence / risk / uncertainty:**
- **Verdict:** Keep | Revise | Remove | Unresolved

## Validation

### Completed

- Exact command or job:
- Snapshot tree/diff hash tested:
- Environment and exit code:
- Result:
- Behavior established:
- Tree modified by validation:

### Missing

- Validation not run:
- Why it matters:
- Recommended command or environment:

## Documentation and operations

- Public contract:
- Compatibility/fallback:
- Rollout/migration:
- Observability:
- Performance:

## Self-review reconciliation

- Manifest hunk count:
- Manifest file-change count:
- Defended change and hunk counts:
- Missing, duplicate, or unknown IDs:
- Arguments revised during adversarial pass:
- Code changes made during self-review:
- Artifacts regenerated after fixes:

## Final recommendation

State what should happen before the next review stage. Do not call the change
ready when blockers or unaccounted hunks remain.
