#!/usr/bin/env python3
"""Validate that a defense report accounts for every review ID exactly once."""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


MARKER = re.compile(r"<!--\s*self-review-id:([CH]\d{3})\s*-->")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact_dir", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    directory = args.artifact_dir.resolve()
    metadata = json.loads((directory / "metadata.json").read_text())
    report = (args.report or directory / "defense-report.md").read_text()
    expected = set(metadata["change_ids"]) | set(metadata["hunk_ids"])
    counts = Counter(MARKER.findall(report))
    found = set(counts)
    missing = sorted(expected - found)
    unknown = sorted(found - expected)
    duplicates = sorted(item for item, count in counts.items() if count != 1)

    if missing or unknown or duplicates:
        if missing:
            print(f"missing markers: {', '.join(missing)}", file=sys.stderr)
        if unknown:
            print(f"unknown markers: {', '.join(unknown)}", file=sys.stderr)
        if duplicates:
            print(f"duplicate markers: {', '.join(duplicates)}", file=sys.stderr)
        return 1
    print(
        f"OK: {len(metadata['change_ids'])} changes and "
        f"{len(metadata['hunk_ids'])} hunks accounted for"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
