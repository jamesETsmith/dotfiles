#!/usr/bin/env python3
"""Extract Crush session digests for skill-mining audits.

Reads the Crush SQLite database (read-only), filters sessions newer than
the last-audit timestamp (or --since), and emits one compact JSON digest
per session on stdout. The agent reads this stream and looks for
recurring workflows worth turning into skills.

Crush stores timestamps as Unix epoch seconds (the column comments in
the schema say milliseconds; they are wrong). All timestamps emitted
and consumed by this script are seconds.

Digest schema (one JSON object per line):
{
  "id":            str,
  "title":         str,
  "created_at":    int (epoch s),
  "updated_at":    int (epoch s),
  "model":         str | null,
  "message_count": int,
  "user_prompts":  [str, ...]        # text from role=user messages, truncated
  "tool_sequence": [{"tool": str, "summary": str}, ...]
}

Exit codes:
  0  success (even if zero sessions matched)
  2  database missing or unreadable
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

DEFAULT_DB = Path(os.path.expanduser("~/.crush/crush.db"))
DEFAULT_STATE = Path(
  os.path.expanduser("~/.agents/state/session-skill-miner/last_audit")
)

MAX_PROMPT_CHARS = 400
MAX_TOOL_SUMMARY_CHARS = 160
MAX_PROMPTS_PER_SESSION = 30
MAX_TOOLS_PER_SESSION = 80


def read_last_audit(path: Path) -> int:
  try:
    return int(path.read_text().strip())
  except (FileNotFoundError, ValueError):
    return 0


def write_last_audit(path: Path, ts_ms: int) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(str(ts_ms))


def truncate(s: str, n: int) -> str:
  s = " ".join(s.split())
  return s if len(s) <= n else s[: n - 1] + "…"


def summarize_tool_call(name: str, raw_input: str) -> str:
  """Produce a one-line summary of a tool invocation."""
  try:
    data = json.loads(raw_input) if isinstance(raw_input, str) else (raw_input or {})
  except json.JSONDecodeError:
    return truncate(str(raw_input), MAX_TOOL_SUMMARY_CHARS)
  if not isinstance(data, dict):
    return truncate(str(data), MAX_TOOL_SUMMARY_CHARS)

  # Prefer the most informative single field per tool.
  for key in (
    "description",
    "command",
    "file_path",
    "path",
    "pattern",
    "query",
    "url",
    "symbol",
  ):
    if key in data and data[key]:
      return truncate(f"{key}={data[key]}", MAX_TOOL_SUMMARY_CHARS)
  return truncate(json.dumps(data, sort_keys=True), MAX_TOOL_SUMMARY_CHARS)


def digest_message_parts(parts_json: str):
  """Yield (kind, payload) tuples for a single message's parts blob."""
  try:
    parts = json.loads(parts_json)
  except json.JSONDecodeError:
    return
  if not isinstance(parts, list):
    return
  for part in parts:
    if not isinstance(part, dict):
      continue
    ptype = part.get("type")
    data = part.get("data") or {}
    if ptype == "text":
      text = data.get("text") if isinstance(data, dict) else None
      if text:
        yield "text", text
    elif ptype in ("tool_call", "tool_use", "tool_invocation"):
      name = (data.get("name") or data.get("toolName") or "?") if isinstance(data, dict) else "?"
      raw_input = data.get("input") if isinstance(data, dict) else None
      yield "tool_call", (name, raw_input)


def build_digest(con: sqlite3.Connection, session_row: sqlite3.Row) -> dict:
  user_prompts: list[str] = []
  tool_sequence: list[dict] = []
  model_seen: str | None = None

  cur = con.execute(
    "SELECT role, parts, model FROM messages "
    "WHERE session_id = ? ORDER BY created_at ASC",
    (session_row["id"],),
  )
  for role, parts_json, model in cur:
    if model and not model_seen:
      model_seen = model
    for kind, payload in digest_message_parts(parts_json):
      if kind == "text" and role == "user":
        if len(user_prompts) < MAX_PROMPTS_PER_SESSION:
          user_prompts.append(truncate(payload, MAX_PROMPT_CHARS))
      elif kind == "tool_call":
        if len(tool_sequence) < MAX_TOOLS_PER_SESSION:
          name, raw_input = payload
          tool_sequence.append(
            {"tool": name, "summary": summarize_tool_call(name, raw_input)}
          )

  return {
    "id": session_row["id"],
    "title": session_row["title"],
    "created_at": session_row["created_at"],
    "updated_at": session_row["updated_at"],
    "model": model_seen,
    "message_count": session_row["message_count"],
    "user_prompts": user_prompts,
    "tool_sequence": tool_sequence,
  }


def main() -> int:
  p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
  p.add_argument("--db", type=Path, default=DEFAULT_DB, help=f"Path to crush.db (default: {DEFAULT_DB})")
  p.add_argument(
    "--state",
    type=Path,
    default=DEFAULT_STATE,
    help=f"Path to last-audit timestamp file (default: {DEFAULT_STATE})",
  )
  p.add_argument(
    "--since",
    type=int,
    default=None,
    help="Epoch seconds; override the stored last-audit timestamp (0 = all sessions).",
  )
  p.add_argument(
    "--mark",
    action="store_true",
    help="After a successful run, update the state file to 'now' so the next audit is incremental.",
  )
  p.add_argument(
    "--min-messages",
    type=int,
    default=4,
    help="Skip sessions with fewer than this many messages (default: 4).",
  )
  p.add_argument(
    "--include-current",
    action="store_true",
    help="Include the currently-running session (default: exclude it to avoid auditing the audit).",
  )
  args = p.parse_args()

  if not args.db.exists():
    print(f"error: database not found at {args.db}", file=sys.stderr)
    return 2

  since_s = args.since if args.since is not None else read_last_audit(args.state)
  current_session = os.environ.get("CRUSH_SESSION_ID", "")

  con = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
  con.row_factory = sqlite3.Row

  now_s = int(time.time())
  rows = con.execute(
    "SELECT id, title, message_count, created_at, updated_at "
    "FROM sessions "
    "WHERE updated_at > ? AND message_count >= ? "
    "ORDER BY created_at ASC",
    (since_s, args.min_messages),
  ).fetchall()

  summary = {
    "_meta": True,
    "db": str(args.db),
    "since_s": since_s,
    "now_s": now_s,
    "session_count": 0,
    "skipped_current": False,
  }

  emitted = 0
  for row in rows:
    if not args.include_current and current_session and row["id"] == current_session:
      summary["skipped_current"] = True
      continue
    digest = build_digest(con, row)
    print(json.dumps(digest, ensure_ascii=False))
    emitted += 1

  summary["session_count"] = emitted
  print(json.dumps(summary, ensure_ascii=False))

  if args.mark and emitted > 0:
    write_last_audit(args.state, now_s)

  return 0


if __name__ == "__main__":
  sys.exit(main())
