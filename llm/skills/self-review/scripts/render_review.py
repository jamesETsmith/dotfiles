#!/usr/bin/env python3
"""Render review.html: the Files Changed preview with the defense report beside it.

The diff keeps its two side-by-side columns. A third column holds one card per
defense-ledger entry, pinned to the first hunk (or file header) that the entry's
`self-review-id` markers name. The report's other sections appear in a panel
above the diff. `files-changed.html` is read, never modified.

Requires the `markdown` package:
    uv run --no-project --with markdown python render_review.py <artifact-dir>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

MARKER = re.compile(r"<!--\s*self-review-id:([CH]\d{3})\s*-->")
FILE_RE = re.compile(r"^## \*\*(C\d{3})\*\*: `(.*?)`")
HUNK_RE = re.compile(r"^- \*\*(H\d{3})\*\*:")
VERDICT_RE = re.compile(r"\*\*Verdict:\*\*\s*([A-Za-z]+)")
TITLE_IDS = re.compile(r"\[(?:[CH]\d{3}(?:,\s*)?)+\]\s*")
LEDGER_HEADING = "## Hunk defense ledger"


def parse_manifest(text: str) -> list[dict]:
    files: list[dict] = []
    for line in text.splitlines():
        match = FILE_RE.match(line)
        if match:
            files.append({"id": match[1], "path": match[2], "hunks": []})
            continue
        match = HUNK_RE.match(line)
        if match:
            if not files:
                raise ValueError(f"hunk {match[1]} precedes any file in the manifest")
            files[-1]["hunks"].append(match[1])
    return files


def split_report(text: str) -> tuple[str, list[dict]]:
    """Return the non-ledger markdown and the ledger entries."""
    lines = text.splitlines()
    try:
        start = next(
            i for i, line in enumerate(lines) if line.strip() == LEDGER_HEADING
        )
    except StopIteration:
        return text, []
    end = next(
        (i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")),
        len(lines),
    )
    entries: list[dict] = []
    current: dict | None = None
    for line in lines[start + 1 : end]:
        if line.startswith("### "):
            title = TITLE_IDS.sub("", line[4:].strip()).replace("``", "")
            current = {"title": title.strip(" —"), "body": []}
            entries.append(current)
        elif current is not None:
            current["body"].append(line)
    for entry in entries:
        body = "\n".join(entry.pop("body"))
        entry["ids"] = MARKER.findall(body)
        entry["body"] = MARKER.sub("", body).strip()
        verdict = VERDICT_RE.search(body)
        entry["verdict"] = verdict[1] if verdict else None
    rest = "\n".join(lines[:start] + lines[end:])
    return rest, [entry for entry in entries if entry["ids"]]


def summary_sections(markdown_text: str) -> list[dict]:
    """Split the non-ledger report into its `##` sections."""
    sections: list[dict] = []
    current = {"title": "", "body": []}
    for line in markdown_text.splitlines():
        if line.startswith("# ") and not sections and not current["body"]:
            continue
        if line.startswith("## "):
            if current["title"] or any(item.strip() for item in current["body"]):
                sections.append(current)
            current = {"title": line[3:].strip(), "body": []}
        else:
            current["body"].append(line)
    sections.append(current)
    return [
        {"title": section["title"], "body": "\n".join(section["body"]).strip()}
        for section in sections
        if section["title"] or "\n".join(section["body"]).strip()
    ]


def to_html(md, text: str, inline: bool = False) -> str:
    md.reset()
    html = md.convert(text)
    if inline and html.startswith("<p>") and html.endswith("</p>"):
        html = html[3:-4]
    return html


OPEN_SECTIONS = {"Executive verdict", "Findings"}

STYLE = """
<style id="self-review-style">
:root { --sr-notes-width: 34%; }
body.sr-ready { text-align: left !important; margin: 0 16px; }
.sr-toolbar { position: sticky; top: 0; z-index: 20; background: #f6f8fa;
  border-bottom: 1px solid #d0d7de; padding: 6px 8px; display: flex; gap: 8px;
  align-items: center; font: 13px -apple-system, "Segoe UI", sans-serif; }
.sr-toolbar button { font: inherit; padding: 2px 10px; cursor: pointer; }
.sr-toolbar .sr-warning { color: #cf222e; font-weight: 600; }
.sr-summary { margin: 12px 0 20px; font: 14px/1.5 -apple-system, "Segoe UI", sans-serif; }
.sr-summary > details { border: 1px solid #d0d7de; border-radius: 6px; margin: 6px 0;
  background: #fff; }
.sr-summary > details > summary { padding: 6px 10px; font-weight: 600; cursor: pointer;
  background: #f6f8fa; }
.sr-summary > details > div { padding: 4px 14px 10px; }
.sr-row { display: flex; align-items: flex-start; gap: 12px; margin-bottom: 1em; }
.sr-diff { flex: 1 1 auto; min-width: 0; }
.sr-diff > .d2h-file-wrapper { margin-bottom: 0; }
.sr-notes { flex: 0 0 var(--sr-notes-width); min-width: 320px; position: relative; }
body.sr-hide-notes .sr-notes { display: none; }
.sr-card { position: absolute; left: 0; right: 0; box-sizing: border-box;
  border: 1px solid #d0d7de; border-left: 4px solid #8c959f; border-radius: 6px;
  background: #fff; font: 13px/1.45 -apple-system, "Segoe UI", sans-serif;
  box-shadow: 0 1px 2px rgba(0,0,0,.06); }
.sr-card.sr-verdict-keep { border-left-color: #1a7f37; }
.sr-card.sr-verdict-revise { border-left-color: #bf8700; }
.sr-card.sr-verdict-remove { border-left-color: #cf222e; }
.sr-card.sr-verdict-unresolved { border-left-color: #8250df; }
.sr-card.sr-missing { border-left-color: #cf222e; background: #fff5f5; }
.sr-card.sr-stub { background: #f6f8fa; }
.sr-card.sr-flash { box-shadow: 0 0 0 3px #54aeff; }
.sr-card > details > summary { padding: 6px 8px; cursor: pointer; list-style: none; }
.sr-card > details > summary::-webkit-details-marker { display: none; }
.sr-card .sr-body { padding: 0 10px 8px; border-top: 1px solid #eaeef2; }
.sr-card .sr-body ul { padding-left: 18px; margin: 6px 0; }
.sr-card, .sr-summary { overflow-wrap: anywhere; }
.sr-card pre, .sr-summary pre { overflow-x: auto; overflow-wrap: normal; }
.sr-card code, .sr-summary code { background: #eff1f3; border-radius: 4px; padding: 0 3px;
  font-size: 90%; }
.sr-chip { display: inline-block; font: 600 11px ui-monospace, monospace; padding: 0 5px;
  margin: 0 3px 2px 0; border-radius: 10px; background: #ddf4ff; color: #0969da; }
.sr-chip.sr-here { background: #0969da; color: #fff; }
.sr-verdict { float: right; font: 600 11px -apple-system, sans-serif; padding: 0 6px;
  border-radius: 10px; background: #eaeef2; }
.sr-hunk-badge { display: inline-block; margin-right: 8px; padding: 0 6px;
  border-radius: 10px; background: #0969da; color: #fff; font: 600 11px monospace;
  cursor: pointer; }
</style>
"""

SCRIPT = r"""
<script>
(function () {
  const data = JSON.parse(document.getElementById("self-review-data").textContent);
  const files = data.files;
  const entries = data.entries;
  const wrappers = Array.from(
    document.querySelectorAll(".d2h-wrapper > .d2h-file-wrapper"));
  document.body.classList.add("sr-ready");

  const el = (tag, cls, html) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (html !== undefined) node.innerHTML = html;
    return node;
  };

  const toolbar = el("div", "sr-toolbar");
  const warnings = [];
  const h1 = document.querySelector("h1");
  if (h1) h1.after(toolbar); else document.body.prepend(toolbar);

  const summary = el("div", "sr-summary");
  for (const section of data.summary) {
    const details = el("details");
    details.open = section.open;
    details.append(el("summary", "", section.title || "Report"),
                   el("div", "", section.html));
    summary.append(details);
  }
  toolbar.after(summary);

  // Anchors: file header for C ids, the hunk's "@@" row for H ids.
  const anchors = {};
  const rows = [];
  if (wrappers.length !== files.length) {
    warnings.push(`diff has ${wrappers.length} files but the manifest has ${files.length}`);
  }
  files.forEach((file, index) => {
    const wrapper = wrappers[index];
    if (!wrapper) return;
    const row = el("div", "sr-row");
    const diff = el("div", "sr-diff");
    const notes = el("div", "sr-notes");
    wrapper.before(row);
    diff.append(wrapper);
    row.append(diff, notes);
    rows.push({ row, diff, notes, cards: [] });
    anchors[file.id] = { file: index, order: -1,
                         node: wrapper.querySelector(".d2h-file-header") || wrapper };
    const side = wrapper.querySelector(".d2h-file-side-diff") || wrapper;
    const headers = Array.from(side.querySelectorAll("tr")).filter((tr) => {
      const line = tr.querySelector("td.d2h-info .d2h-code-side-line, " +
                                    "td.d2h-info .d2h-code-line");
      return line && line.textContent.trim().startsWith("@@");
    });
    if (headers.length !== file.hunks.length) {
      warnings.push(`${file.path}: ${headers.length} hunks in HTML, ` +
                    `${file.hunks.length} in manifest`);
    }
    file.hunks.forEach((hunkId, k) => {
      const tr = headers[k];
      if (!tr) return;
      anchors[hunkId] = { file: index, order: k, node: tr };
      const line = tr.querySelector(".d2h-code-side-line, .d2h-code-line");
      if (line) {
        const badge = el("span", "sr-hunk-badge", hunkId);
        badge.title = "Show the defense for " + hunkId;
        badge.addEventListener("click", () => focusCard(hunkId));
        line.prepend(badge);
      }
    });
  });

  const cardFor = {};
  const chips = (ids, here) => ids.map((id) =>
    `<span class="sr-chip${here.includes(id) ? " sr-here" : ""}">${id}</span>`).join("");

  function addCard(fileIndex, anchor, node) {
    node._anchor = anchor;
    rows[fileIndex].notes.append(node);
    rows[fileIndex].cards.push(node);
  }

  const covered = new Set();
  entries.forEach((entry, n) => {
    const byFile = new Map();
    for (const id of entry.ids) {
      const anchor = anchors[id];
      if (!anchor) continue;
      covered.add(id);
      if (!byFile.has(anchor.file)) byFile.set(anchor.file, []);
      byFile.get(anchor.file).push({ id, anchor });
    }
    const fileOrder = Array.from(byFile.keys()).sort((a, b) => a - b);
    fileOrder.forEach((fileIndex, i) => {
      const items = byFile.get(fileIndex).sort((a, b) => a.anchor.order - b.anchor.order);
      const here = items.map((item) => item.id);
      const verdict = (entry.verdict || "").toLowerCase();
      const card = el("div", "sr-card" + (verdict ? " sr-verdict-" + verdict : "") +
                      (i ? " sr-stub" : ""));
      card.id = i ? `sr-entry-${n}-${fileIndex}` : `sr-entry-${n}`;
      const head = `${chips(entry.ids, here)}` +
        (entry.verdict ? `<span class="sr-verdict">${entry.verdict}</span>` : "") +
        `<div>${entry.title}</div>`;
      if (i) {
        card.innerHTML = `<details><summary>${head}</summary><div class="sr-body">` +
          `<p>Defended with <a href="#sr-entry-${n}">its first file</a>.</p>` +
          `${entry.html}</div></details>`;
      } else {
        card.innerHTML = `<details open><summary>${head}</summary>` +
          `<div class="sr-body">${entry.html}</div></details>`;
      }
      for (const id of here) cardFor[id] = card;
      addCard(fileIndex, items[0].anchor, card);
    });
  });

  for (const [id, anchor] of Object.entries(anchors)) {
    if (covered.has(id)) continue;
    const card = el("div", "sr-card sr-missing",
      `<details open><summary>${chips([id], [id])}<div><b>No defense entry</b></div>` +
      `</summary><div class="sr-body"><p>Add a ledger entry with ` +
      `<code>&lt;!-- self-review-id:${id} --&gt;</code>.</p></div></details>`);
    cardFor[id] = card;
    addCard(anchor.file, anchor, card);
    warnings.push(`no defense entry for ${id}`);
  }

  function layout() {
    for (const { notes, cards } of rows) {
      const base = notes.getBoundingClientRect().top;
      const sorted = cards.slice().sort((a, b) =>
        a._anchor.node.getBoundingClientRect().top -
        b._anchor.node.getBoundingClientRect().top);
      let cursor = 0;
      for (const card of sorted) {
        const want = card._anchor.node.getBoundingClientRect().top - base;
        const top = Math.max(want, cursor);
        card.style.top = top + "px";
        cursor = top + card.offsetHeight + 8;
      }
      notes.style.minHeight = cursor + "px";
    }
  }

  function focusCard(id) {
    const card = cardFor[id];
    if (!card) return;
    document.body.classList.remove("sr-hide-notes");
    const details = card.querySelector("details");
    if (details && !details.open) details.open = true;
    layout();
    card.scrollIntoView({ behavior: "smooth", block: "center" });
    card.classList.add("sr-flash");
    setTimeout(() => card.classList.remove("sr-flash"), 1200);
  }

  const button = (label, action) => {
    const node = el("button", "", label);
    node.addEventListener("click", () => { action(); layout(); });
    toolbar.append(node);
  };
  toolbar.append(el("b", "", "Defense notes"));
  button("Hide/show notes", () => document.body.classList.toggle("sr-hide-notes"));
  button("Expand all", () => document.querySelectorAll(".sr-card details")
    .forEach((d) => { d.open = true; }));
  button("Collapse all", () => document.querySelectorAll(".sr-card details")
    .forEach((d) => { d.open = false; }));
  const status = el("span", warnings.length ? "sr-warning" : "",
    warnings.length ? `${warnings.length} problem(s): ${warnings.join("; ")}`
                    : `${entries.length} entries, ${Object.keys(anchors).length} IDs placed`);
  toolbar.append(status);

  document.querySelectorAll(".sr-card details")
    .forEach((d) => d.addEventListener("toggle", layout));
  const observer = new ResizeObserver(() => layout());
  rows.forEach(({ diff, notes }) => { observer.observe(diff); observer.observe(notes); });
  window.addEventListener("resize", layout);
  layout();
})();
</script>
"""


def render(directory: Path, report_path: Path, output: Path) -> dict:
    try:
        import markdown
    except ImportError as exc:
        raise RuntimeError(
            "render_review.py needs the markdown package; run it with "
            "`uv run --no-project --with markdown python render_review.py ...`"
        ) from exc

    md = markdown.Markdown(extensions=["tables", "fenced_code", "sane_lists"])
    html_path = directory / "files-changed.html"
    source = html_path.read_text(encoding="utf-8")
    files = parse_manifest((directory / "hunk-manifest.md").read_text(encoding="utf-8"))
    rest, entries = split_report(report_path.read_text(encoding="utf-8"))

    data = {
        "files": files,
        "entries": [
            {
                "ids": entry["ids"],
                "title": to_html(md, entry["title"], inline=True),
                "verdict": entry["verdict"],
                "html": to_html(md, entry["body"]),
            }
            for entry in entries
        ],
        "summary": [
            {
                "title": section["title"],
                "open": section["title"] in OPEN_SECTIONS,
                "html": to_html(md, section["body"]),
            }
            for section in summary_sections(rest)
        ],
    }
    blob = json.dumps(data).replace("</", "<\\/")
    payload = (
        f'<script id="self-review-data" type="application/json">{blob}</script>'
        + SCRIPT
    )
    if "</head>" not in source or "</body>" not in source:
        raise RuntimeError("files-changed.html has no </head> or </body>")
    head_at = source.index("</head>")
    body_at = source.rindex("</body>")
    rendered = (
        source[:head_at] + STYLE + source[head_at:body_at] + payload + source[body_at:]
    )
    output.write_text(rendered, encoding="utf-8")

    placed = {id_ for entry in entries for id_ in entry["ids"]}
    expected = {f["id"] for f in files} | {h for f in files for h in f["hunks"]}
    return {
        "review_html": str(output),
        "review_html_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "source_html_sha256": hashlib.sha256(html_path.read_bytes()).hexdigest(),
        "report_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest(),
        "entries": len(entries),
        "missing_ids": sorted(expected - placed),
        "unknown_ids": sorted(placed - expected),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("artifact_dir", type=Path)
    parser.add_argument(
        "--report", type=Path, help="default: <artifact-dir>/defense-report.md"
    )
    parser.add_argument(
        "--output", type=Path, help="default: <artifact-dir>/review.html"
    )
    args = parser.parse_args()
    directory = args.artifact_dir.resolve()
    result = render(
        directory,
        (args.report or directory / "defense-report.md").resolve(),
        (args.output or directory / "review.html").resolve(),
    )
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
