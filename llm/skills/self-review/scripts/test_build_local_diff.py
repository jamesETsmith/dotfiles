#!/usr/bin/env python3
"""Focused tests for local snapshot and PR comparison semantics."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_local_diff.py")
SPEC = importlib.util.spec_from_file_location("build_local_diff", MODULE_PATH)
assert SPEC and SPEC.loader
builder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = builder
SPEC.loader.exec_module(builder)


def command(repo: Path, *args: str) -> str:
    return subprocess.run(
        args,
        cwd=repo,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


class LocalDiffTest(unittest.TestCase):
    def test_normal_branch_uses_merge_base_and_captures_untracked_empty_file(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            command(repo, "git", "init", "-b", "main")
            command(repo, "git", "config", "user.email", "self-review@example.com")
            command(repo, "git", "config", "user.name", "Self Review")
            (repo / "feature.txt").write_text("base\n")
            (repo / "rename-me.txt").write_text("rename\n")
            command(repo, "git", "add", ".")
            command(repo, "git", "commit", "-m", "base")
            original_base = command(repo, "git", "rev-parse", "HEAD")

            command(repo, "git", "switch", "-c", "feature")
            (repo / "feature.txt").write_text("feature\n")
            (repo / "rename-me.txt").rename(repo / "renamed.txt")
            (repo / "binary.bin").write_bytes(b"\x00\x01\xff")
            command(repo, "git", "add", ".")
            command(repo, "git", "commit", "-m", "feature")

            command(repo, "git", "switch", "main")
            (repo / "upstream-only.txt").write_text("upstream\n")
            command(repo, "git", "add", ".")
            command(repo, "git", "commit", "-m", "advance main")
            base_tip = command(repo, "git", "rev-parse", "HEAD")

            command(repo, "git", "switch", "feature")
            (repo / "feature.txt").write_text("feature plus local\n")
            (repo / "empty.txt").touch()

            head = builder.git(repo, "rev-parse", "HEAD").strip()
            before, mode = builder.comparison_commit(
                repo,
                base_commit=base_tip,
                head_commit=head,
                mode="auto",
            )
            self.assertEqual(mode, "merge-base")
            self.assertEqual(before, original_base)

            tree = builder.snapshot_tree(repo, None)
            diff = builder.local_diff(repo, before, tree)
            files = builder.raw_file_records(repo, before, tree)
            builder.attach_hunks(diff, files)

            by_path = {item.path: item for item in files}
            self.assertNotIn("upstream-only.txt", by_path)
            self.assertEqual(by_path["renamed.txt"].status, "renamed")
            self.assertEqual(by_path["renamed.txt"].old_path, "rename-me.txt")
            self.assertEqual(by_path["binary.bin"].status, "added")
            self.assertEqual(by_path["empty.txt"].status, "added")
            self.assertEqual(by_path["empty.txt"].hunks, [])

    def test_report_validator_requires_each_change_and_hunk_once(self):
        validator = Path(__file__).with_name("validate_report.py")
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            (directory / "metadata.json").write_text(
                '{"change_ids":["C001"],"hunk_ids":["H001"]}'
            )
            report = directory / "defense-report.md"
            report.write_text(
                "<!-- self-review-id:C001 -->\n"
                "<!-- self-review-id:H001 -->\n"
            )
            ok = subprocess.run(
                [sys.executable, str(validator), str(directory)],
                check=False,
            )
            self.assertEqual(ok.returncode, 0)

            report.write_text("<!-- self-review-id:C001 -->\n")
            missing = subprocess.run(
                [sys.executable, str(validator), str(directory)],
                check=False,
            )
            self.assertEqual(missing.returncode, 1)

    def test_review_render_places_entries_and_reports_missing_ids(self):
        try:
            import markdown  # noqa: F401
        except ImportError:
            self.skipTest("markdown is not installed; run with --with markdown")
        render_spec = importlib.util.spec_from_file_location(
            "render_review", Path(__file__).with_name("render_review.py")
        )
        assert render_spec and render_spec.loader
        renderer = importlib.util.module_from_spec(render_spec)
        render_spec.loader.exec_module(renderer)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            source = "<html><head></head><body><h1>t</h1></body></html>"
            (directory / "files-changed.html").write_text(source)
            (directory / "hunk-manifest.md").write_text(
                "# Self-review hunk manifest\n\n"
                "## **C001**: `a.py` (modified)\n\n"
                "- **H001**: old 1-2, new 1-3\n"
                "- **H002**: old 9-9, new 10-10\n"
            )
            (directory / "defense-report.md").write_text(
                "# Self-review defense report\n\n"
                "## Executive verdict\n\nReady.\n\n"
                "## Hunk defense ledger\n\n"
                "### `[C001, H001] a.py` — first change\n"
                "<!-- self-review-id:C001 -->\n"
                "<!-- self-review-id:H001 -->\n\n"
                "- **Verdict:** Keep\n\n"
                "## Validation\n\nNone.\n"
            )
            result = renderer.render(
                directory,
                directory / "defense-report.md",
                directory / "review.html",
            )
            self.assertEqual(result["entries"], 1)
            self.assertEqual(result["missing_ids"], ["H002"])
            self.assertEqual(result["unknown_ids"], [])
            html = (directory / "review.html").read_text()
            self.assertIn('id="self-review-data"', html)
            self.assertIn("first change", html)
            self.assertIn('"verdict": "Keep"', html)
            blob = html.split('type="application/json">', 1)[1].split("</script>", 1)[0]
            self.assertNotIn("self-review-id", blob)
            self.assertEqual((directory / "files-changed.html").read_text(), source)


if __name__ == "__main__":
    unittest.main()
