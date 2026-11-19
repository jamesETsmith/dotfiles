#!/usr/bin/env python3
"""List recent posts from the AI research blogs tracked by the ai-research-digest skill.

Stdlib only. Prints JSON (default) or a Markdown table of posts, newest first,
with a per-source status so failures are visible instead of silently dropped.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import email.utils
import html
import http.client
import time
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SOURCES_FILE = SCRIPT_DIR.parent / "sources.json"
DEFAULT_STATE = Path(
    os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")
) / "ai-research-digest" / "seen.json"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) ai-research-digest/1.0"
TIMEOUT = 60

MONTHS = {
    m: i + 1
    for i, m in enumerate(
        ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    )
}
DATE_PATTERNS = [
    re.compile(r"datetime=\"(\d{4}-\d{2}-\d{2})", re.I),
    re.compile(r"(?<![\w/-])(\d{4}-\d{2}-\d{2})(?![\w-]*[a-z])"),
    re.compile(r"\b(\d{2})\.(\d{2})\.(\d{4})\b"),
    re.compile(
        r"\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b",
        re.I,
    ),
    re.compile(
        r"\b(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?,?\s+(\d{4})\b",
        re.I,
    ),
    re.compile(r"\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)\s+(\d{4})\b"),
]


def fetch(url: str, attempts: int = 3) -> str:
    req = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "identity"}
    )
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read().decode("utf-8", "replace")
        except (http.client.IncompleteRead, ConnectionError, TimeoutError, urllib.error.URLError):
            if attempt == attempts - 1:
                raise
            time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def _match_to_date(idx: int, m: re.Match) -> dt.date | None:
    try:
        if idx in (0, 1):
            d = dt.date.fromisoformat(m.group(1))
        elif idx == 2:
            d = dt.date(int(m.group(3)), int(m.group(1)), int(m.group(2)))
        elif idx == 3:
            d = dt.date(int(m.group(3)), MONTHS[m.group(1)[:3].lower()], int(m.group(2)))
        elif idx == 4:
            d = dt.date(int(m.group(3)), MONTHS[m.group(2)[:3].lower()], int(m.group(1)))
        else:
            d = dt.date(int(m.group(2)), MONTHS[m.group(1)[:3].lower()], 1)
    except (ValueError, KeyError):
        return None
    return d if 2015 <= d.year <= 2100 else None


def parse_date(text: str, last: bool = False) -> str | None:
    """Return the first (or last) date that appears in text, by position."""
    found: list[tuple[int, dt.date]] = []
    for idx, pat in enumerate(DATE_PATTERNS):
        for m in pat.finditer(text):
            d = _match_to_date(idx, m)
            if d:
                found.append((m.start(), d))
    if not found:
        return None
    found.sort(key=lambda item: item[0])
    return (found[-1] if last else found[0])[1].isoformat()


def strip_tags(fragment: str) -> str:
    fragment = re.sub(r"<(script|style|svg)\b.*?</\1>", " ", fragment, flags=re.S | re.I)
    text = re.sub(r"<[^>]+>", " ", fragment)
    return re.sub(r"\s+", " ", html.unescape(text)).strip()


def rss_date(value: str | None) -> str | None:
    if not value:
        return None
    value = value.strip()
    try:
        return email.utils.parsedate_to_datetime(value).date().isoformat()
    except (TypeError, ValueError):
        pass
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).date().isoformat()
    except ValueError:
        return parse_date(value)


def from_rss(source: dict) -> list[dict]:
    root = ET.fromstring(fetch(source["feed"]))
    posts = []
    atom = "{http://www.w3.org/2005/Atom}"
    items = root.findall(".//item") or root.findall(f".//{atom}entry")
    for item in items:
        title = item.findtext("title") or item.findtext(f"{atom}title") or ""
        link = item.findtext("link")
        if not link:
            el = item.find(f"{atom}link")
            link = el.get("href") if el is not None else ""
        date = rss_date(
            item.findtext("pubDate")
            or item.findtext(f"{atom}published")
            or item.findtext(f"{atom}updated")
        )
        summary = item.findtext("description") or item.findtext(f"{atom}summary") or ""
        posts.append(
            {
                "title": strip_tags(title) or link.rstrip("/").rsplit("/", 1)[-1],
                "url": (link or "").strip(),
                "date": date,
                "summary": strip_tags(summary)[:300],
            }
        )
    return posts


def _first(pattern: str | None, text: str) -> str:
    if not pattern:
        return ""
    m = re.search(pattern, text, re.S | re.I)
    return strip_tags(m.group(1)) if m else ""


def from_html(source: dict) -> list[dict]:
    """Scrape a listing page.

    Block mode (``item_split`` set): split the page into per-post blocks, then take
    the first matching link, ``title_regex`` capture, and first date in each block.

    Anchor mode: each ``<a>`` whose href matches ``link_regex`` is a post. Title comes
    from ``title_regex`` applied to the anchor body (falls back to anchor text). The
    date is searched in the anchor body, then in the text after (``date_position``
    "after", default) or before ("before") the anchor.
    """
    page = fetch(source["listing"])
    link_re = re.compile(source["link_regex"])
    posts: dict[str, dict] = {}

    def add(url: str, title: str, date: str | None, summary: str, strong: bool) -> None:
        url = urllib.parse.urljoin(source["listing"], url)
        title = re.sub(r"\s+", " ", title).strip(" ·|-")
        key = url.rstrip("/")
        old = posts.get(key)
        if old:
            if strong and not old["_strong"]:
                old.update(title=title or old["title"], _strong=True)
            elif strong == old["_strong"] and 8 <= len(title) < len(old["title"]):
                old["title"] = title
            old["date"] = old["date"] or date
            old["summary"] = old["summary"] or summary
            return
        posts[key] = {"title": title or url, "url": url, "date": date, "summary": summary, "_strong": strong}

    if source.get("item_split"):
        for block in re.split(source["item_split"], page)[1:]:
            hrefs = [h for h in re.findall(r"href=\"([^\"#]+)\"", block) if link_re.search(h)]
            if not hrefs:
                continue
            title = _first(source.get("title_regex"), block)
            if source.get("require_title", True) and not title:
                continue
            add(hrefs[0], title, parse_date(block), _first(source.get("summary_regex"), block), bool(title))
    else:
        window = int(source.get("date_window", 600))
        before_mode = source.get("date_position") == "before"
        for m in re.finditer(r"<a\b[^>]*href=\"([^\"#?]+)\"[^>]*>(.*?)</a>", page, re.S | re.I):
            href, inner = m.group(1), m.group(2)
            if not link_re.search(href):
                continue
            title = _first(source.get("title_regex"), inner)
            strong = bool(title)
            if source.get("require_title") and not strong:
                continue
            title = title or strip_tags(inner)
            if before_mode:
                ctx = parse_date(page[max(0, m.start() - window) : m.start()], last=True)
            else:
                ctx = parse_date(page[m.end() : m.end() + window])
            date = parse_date(inner) or ctx
            add(href, title, date, _first(source.get("summary_regex"), inner), strong)

    for post in posts.values():
        post.pop("_strong", None)
    return list(posts.values())


def from_qwen(source: dict) -> list[dict]:
    data = json.loads(fetch(source["api"]))
    posts = []
    for art in data.get("data", {}).get("articles", []):
        extra = art.get("extra") or {}
        posts.append(
            {
                "title": art.get("title", ""),
                "url": source["post_url"].format(path=art.get("path", "")),
                "date": rss_date(extra.get("date")) or parse_date(str(extra.get("date", ""))),
                "summary": strip_tags(extra.get("description") or extra.get("introduction") or "")[:300],
                "tags": extra.get("tags", []),
            }
        )
    return posts


STRATEGIES = {"rss": from_rss, "html": from_html, "qwen_api": from_qwen}

PUBLISHED_PATTERNS = [
    re.compile(r'property="article:published_time"\s+content="([^"]+)"', re.I),
    re.compile(r'content="([^"]+)"\s+property="article:published_time"', re.I),
    re.compile(r'"datePublished"\s*:\s*"([^"]+)"'),
]


def exact_date(url: str) -> str | None:
    """Read a post page's published-time metadata, for listings that only show the month."""
    try:
        page = fetch(url)
    except Exception:  # noqa: BLE001 - fall back to the listing's month
        return None
    for pat in PUBLISHED_PATTERNS:
        m = pat.search(page)
        if m:
            return rss_date(m.group(1))
    return None


def collect(source: dict) -> dict:
    try:
        posts = STRATEGIES[source["strategy"]](source)
        posts = [p for p in posts if p.get("url")]
        for p in posts:
            p["source"] = source["name"]
        dated = sum(1 for p in posts if p.get("date"))
        status = "ok" if posts else "empty"
        return {"name": source["name"], "status": status, "count": len(posts), "dated": dated, "posts": posts}
    except Exception as exc:  # noqa: BLE001 - report every failure per source
        return {"name": source["name"], "status": f"error: {type(exc).__name__}: {exc}", "count": 0, "dated": 0, "posts": []}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--days", type=int, default=7, help="Keep posts dated within N days (default 7). 0 disables.")
    parser.add_argument("--since", help="Keep posts on/after YYYY-MM-DD (overrides --days).")
    parser.add_argument("--per-source", type=int, default=10, help="Max posts kept per source (default 10).")
    parser.add_argument("--source", action="append", help="Only these source names (repeatable).")
    parser.add_argument("--format", choices=["json", "md"], default="json")
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE, help="Seen-URL state file.")
    parser.add_argument("--mark-seen", action="store_true", help="Record returned URLs in the state file.")
    parser.add_argument("--include-undated", action="store_true", help="Keep posts whose date could not be parsed.")
    args = parser.parse_args()

    sources = json.loads(SOURCES_FILE.read_text())["sources"]
    if args.source:
        wanted = {s.lower() for s in args.source}
        sources = [s for s in sources if s["name"].lower() in wanted]

    cutoff = None
    if args.since:
        cutoff = dt.date.fromisoformat(args.since)
    elif args.days > 0:
        cutoff = dt.date.today() - dt.timedelta(days=args.days)

    seen: set[str] = set()
    if args.state.exists():
        seen = set(json.loads(args.state.read_text()).get("urls", []))

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(collect, sources))

    month_precision = {s["name"] for s in sources if s.get("date_precision") == "month"}

    def effective_date(post: dict) -> dt.date:
        day = dt.date.fromisoformat(post["date"])
        if post["source"] in month_precision:
            nxt = (day.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
            return nxt - dt.timedelta(days=1)
        return day

    refine = [
        p
        for res in results
        for p in res["posts"][: args.per_source * 2]
        if p["source"] in month_precision and p.get("date") and (not cutoff or effective_date(p) >= cutoff)
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        for p, exact in zip(refine, pool.map(lambda post: exact_date(post["url"]), refine)):
            if exact:
                p["date"] = exact
                p["date_exact"] = True

    kept_all = []
    for res in results:
        posts = res.pop("posts")
        posts.sort(key=lambda p: p.get("date") or "", reverse=True)
        kept = []
        for p in posts:
            if p.get("date") is None and not args.include_undated:
                continue
            if p.get("date") and p["source"] in month_precision and not p.pop("date_exact", False):
                p["date_precision"] = "month"
            if cutoff and p.get("date") and (
                effective_date(p) if p.get("date_precision") else dt.date.fromisoformat(p["date"])
            ) < cutoff:
                continue
            p["new"] = p["url"] not in seen
            kept.append(p)
        res["kept"] = len(kept[: args.per_source])
        kept_all.extend(kept[: args.per_source])

    kept_all.sort(key=lambda p: (p.get("date") or "", p["source"]), reverse=True)

    if args.mark_seen:
        args.state.parent.mkdir(parents=True, exist_ok=True)
        seen.update(p["url"] for p in kept_all)
        args.state.write_text(json.dumps({"updated": dt.datetime.now().isoformat(), "urls": sorted(seen)}, indent=1))

    window = {"since": cutoff.isoformat() if cutoff else None, "until": dt.date.today().isoformat()}
    if args.format == "json":
        json.dump({"window": window, "sources": results, "posts": kept_all}, sys.stdout, indent=2)
        print()
    else:
        print(f"Window: {window['since'] or 'all'} to {window['until']}\n")
        print("| Source | Status | Found | Dated | Kept |\n|---|---|---|---|---|")
        for r in results:
            print(f"| {r['name']} | {r['status']} | {r['count']} | {r['dated']} | {r['kept']} |")
        print("\n| Date | Source | New | Title | URL |\n|---|---|---|---|---|")
        for p in kept_all:
            title = p["title"].replace("|", "\\|")
            date = (p.get("date") or "?")[: 7 if p.get("date_precision") == "month" else 10]
            print(f"| {date} | {p['source']} | {'yes' if p['new'] else ''} | {title} | {p['url']} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
