#!/usr/bin/env python3
"""Print the readable text of a blog post, for sites where a plain fetch is not enough.

Qwen posts (qwen.ai/blog?id=...) are rendered client-side, so their body is pulled
from the JSON API that backs qwen.ai/research. Other URLs are fetched and reduced to
the text of <article> (or <main>, or <body>), keeping headings, list items, and tables
as simple Markdown-ish lines.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_index import SOURCES_FILE, fetch  # noqa: E402


def html_to_text(fragment: str) -> str:
    fragment = re.sub(r"<(script|style|svg|noscript|nav|footer|header)\b.*?</\1>", " ", fragment, flags=re.S | re.I)
    fragment = re.sub(r"<h([1-6])[^>]*>", lambda m: "\n\n" + "#" * int(m.group(1)) + " ", fragment, flags=re.I)
    fragment = re.sub(r"<li[^>]*>", "\n- ", fragment, flags=re.I)
    fragment = re.sub(r"<t[dh][^>]*>", " | ", fragment, flags=re.I)
    fragment = re.sub(r"</tr>", " |\n", fragment, flags=re.I)
    fragment = re.sub(r"<(br|/p|/div|/h[1-6]|/pre|/blockquote|/table)[^>]*>", "\n", fragment, flags=re.I)
    text = html.unescape(re.sub(r"<[^>]+>", "", fragment))
    text = re.sub(r"[ \t\u00a0]+", " ", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def main_fragment(page: str) -> str:
    for tag in ("article", "main"):
        blocks = re.findall(rf"<{tag}\b.*?</{tag}>", page, re.S | re.I)
        if blocks:
            return max(blocks, key=len)
    m = re.search(r"<body\b.*?</body>", page, re.S | re.I)
    return m.group(0) if m else page


def read_qwen(post_id: str) -> str:
    sources = json.loads(SOURCES_FILE.read_text())["sources"]
    api = next(s["api"] for s in sources if s["strategy"] == "qwen_api")
    for art in json.loads(fetch(api))["data"]["articles"]:
        if art.get("path") == post_id:
            extra = art.get("extra") or {}
            body = html_to_text(main_fragment(art.get("content") or ""))
            return f"# {art.get('title')}\nDate: {extra.get('date')}\nTags: {', '.join(extra.get('tags') or [])}\n\n{body}"
    raise SystemExit(f"Qwen post id {post_id!r} not found in API response")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("--max-chars", type=int, default=60000, help="Truncate output (default 60000, 0 = no limit).")
    args = parser.parse_args()

    parsed = urllib.parse.urlparse(args.url)
    qs = urllib.parse.parse_qs(parsed.query)
    if parsed.netloc.endswith("qwen.ai") and parsed.path.startswith("/blog") and "id" in qs:
        text = read_qwen(qs["id"][0])
    else:
        page = fetch(args.url)
        title = re.search(r"<title[^>]*>(.*?)</title>", page, re.S | re.I)
        text = (f"# {html.unescape(title.group(1).strip())}\n\n" if title else "") + html_to_text(main_fragment(page))

    if args.max_chars and len(text) > args.max_chars:
        text = text[: args.max_chars] + f"\n\n[truncated at {args.max_chars} chars]"
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
