#!/usr/bin/env python3
"""Build and serve local self-review artifacts for a Git working tree."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import functools
import hashlib
import http.server
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path


DIFF2HTML_VERSION = "5.2.15"
HUNK_RE = re.compile(
    r"^@@ -(?P<old>\d+)(?:,(?P<old_count>\d+))? "
    r"\+(?P<new>\d+)(?:,(?P<new_count>\d+))? @@(?P<context>.*)$"
)


def run(
    args: list[str],
    *,
    cwd: Path,
    check: bool = True,
    text: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        cwd=cwd,
        check=check,
        text=text,
        encoding="utf-8" if text else None,
        errors="surrogateescape" if text else None,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def git(
    repo: Path,
    *args: str,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> str:
    return run(["git", *args], cwd=repo, check=check, env=env).stdout


def repo_root(path: Path) -> Path:
    root = run(
        ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
        cwd=path,
    ).stdout.strip()
    return Path(root).resolve()


def branch_slug(repo: Path) -> str:
    branch = git(repo, "branch", "--show-current").strip() or "detached-head"
    return re.sub(r"[^A-Za-z0-9._-]+", "-", branch).strip("-") or "review"


def default_output(repo: Path) -> Path:
    raw = git(
        repo,
        "rev-parse",
        "--git-path",
        f"self-review/{branch_slug(repo)}",
    ).strip()
    path = Path(raw)
    return (repo / path).resolve() if not path.is_absolute() else path.resolve()


def relative_output(repo: Path, output: Path) -> str | None:
    try:
        return output.resolve().relative_to(repo).as_posix()
    except ValueError:
        return None


def status_bytes(repo: Path, output_rel: str | None) -> bytes:
    command = [
        "git",
        "status",
        "--porcelain=v2",
        "-z",
        "--untracked-files=all",
        "--",
        ".",
    ]
    if output_rel:
        command.append(f":(exclude){output_rel}/**")
    return run(command, cwd=repo, text=False).stdout


def porcelain_record_types(raw: bytes) -> Counter:
    counts: Counter = Counter()
    records = raw.split(b"\0")
    i = 0
    while i < len(records):
        record = records[i]
        i += 1
        if not record:
            continue
        kind = chr(record[0])
        counts[kind] += 1
        if kind == "2" and i < len(records):
            i += 1  # rename/copy's original path
    return counts


def snapshot_tree(repo: Path, output_rel: str | None) -> str:
    """Write a temporary-index tree for the final tracked + untracked snapshot."""
    with tempfile.TemporaryDirectory(prefix="self-review-index-") as temp:
        index = Path(temp) / "index"
        env = {**os.environ, "GIT_INDEX_FILE": str(index)}
        git(repo, "read-tree", "HEAD", env=env)
        git(repo, "add", "-A", "--", ".", env=env)
        if output_rel:
            tracked = run(
                ["git", "ls-files", "--error-unmatch", "--", output_rel],
                cwd=repo,
                check=False,
            )
            if tracked.returncode == 0:
                raise RuntimeError(
                    f"artifact output is tracked and would contaminate review: "
                    f"{output_rel}"
                )
            git(repo, "reset", "-q", "HEAD", "--", output_rel, env=env)
        return git(repo, "write-tree", env=env).strip()


def merge_heads(repo: Path) -> list[str]:
    path = Path(git(repo, "rev-parse", "--absolute-git-dir").strip()) / "MERGE_HEAD"
    return path.read_text().splitlines() if path.exists() else []


def comparison_commit(
    repo: Path,
    *,
    base_commit: str,
    head_commit: str,
    mode: str,
) -> tuple[str, str]:
    heads = merge_heads(repo)
    if mode == "auto":
        mode = "base" if base_commit in heads else "merge-base"
    if mode == "base":
        return base_commit, mode
    commit = git(repo, "merge-base", base_commit, head_commit).strip()
    if not commit:
        raise RuntimeError(f"no merge base between {base_commit} and {head_commit}")
    return commit, mode


def local_diff(repo: Path, before: str, after_tree: str) -> str:
    return git(
        repo,
        "-c",
        "core.quotePath=false",
        "diff",
        "--full-index",
        "--binary",
        "--find-renames",
        "--find-copies",
        "--no-ext-diff",
        "--no-textconv",
        "--src-prefix=a/",
        "--dst-prefix=b/",
        before,
        after_tree,
        "--",
    )


def nul_paths(repo: Path, *args: str) -> list[str]:
    raw = run(["git", *args, "-z"], cwd=repo, text=False).stdout
    return [
        item.decode("utf-8", errors="surrogateescape")
        for item in raw.split(b"\0")
        if item
    ]


def provenance(
    repo: Path,
    *,
    base_commit: str,
    head_commit: str,
    status_raw: bytes,
) -> dict:
    original_merge_base = git(repo, "merge-base", base_commit, head_commit).strip()
    layers = {
        "committed": nul_paths(
            repo,
            "diff",
            "--name-only",
            original_merge_base,
            head_commit,
        ),
        "staged": nul_paths(repo, "diff", "--cached", "--name-only"),
        "unstaged": nul_paths(repo, "diff", "--name-only"),
        "untracked": nul_paths(
            repo,
            "ls-files",
            "--others",
            "--exclude-standard",
        ),
    }
    return {
        "layers": layers,
        "porcelain_v2_z_base64": base64.b64encode(status_raw).decode("ascii"),
        "submodules": git(repo, "submodule", "status", "--recursive").splitlines(),
    }


def apply_sources(files: list[FileDiff], provenance_data: dict) -> None:
    layer_paths = {
        layer: set(paths) for layer, paths in provenance_data["layers"].items()
    }
    for item in files:
        aliases = {item.path}
        if item.old_path:
            aliases.add(item.old_path)
        item.sources = [
            layer
            for layer, paths in layer_paths.items()
            if not aliases.isdisjoint(paths)
        ]


@dataclass
class FileDiff:
    change_id: str
    path: str
    old_path: str | None = None
    status: str = "modified"
    sources: list[str] = field(default_factory=list)
    hunks: list[dict] = field(default_factory=list)


def raw_file_records(repo: Path, before: str, after: str) -> list[FileDiff]:
    raw = run(
        [
            "git",
            "diff",
            "--raw",
            "-z",
            "--find-renames",
            "--find-copies",
            before,
            after,
            "--",
        ],
        cwd=repo,
        text=False,
    ).stdout
    tokens = raw.split(b"\0")
    files: list[FileDiff] = []
    i = 0
    names = {
        "A": "added",
        "C": "copied",
        "D": "deleted",
        "M": "modified",
        "R": "renamed",
        "T": "type-changed",
        "U": "unmerged",
        "X": "unknown",
    }
    while i < len(tokens) and tokens[i]:
        header = tokens[i].decode("ascii")
        i += 1
        fields = header.split()
        if len(fields) != 5 or not fields[0].startswith(":"):
            raise RuntimeError(f"unexpected raw diff record: {header!r}")
        status_code = fields[4]
        old_path = tokens[i].decode("utf-8", errors="surrogateescape")
        i += 1
        new_path = old_path
        if status_code[0] in {"R", "C"}:
            new_path = tokens[i].decode("utf-8", errors="surrogateescape")
            i += 1
        files.append(
            FileDiff(
                change_id=f"C{len(files) + 1:03d}",
                path=new_path,
                old_path=old_path if old_path != new_path else None,
                status=names.get(status_code[0], status_code),
            )
        )
    return files


def attach_hunks(diff: str, files: list[FileDiff]) -> None:
    current: FileDiff | None = None
    file_index = 0
    hunk_number = 0
    for line in diff.splitlines():
        if line.startswith("diff --git "):
            if file_index >= len(files):
                raise RuntimeError("text diff has more file records than raw diff")
            current = files[file_index]
            file_index += 1
            continue
        if current is None:
            continue
        match = HUNK_RE.match(line)
        if match:
            hunk_number += 1
            values = match.groupdict()
            current.hunks.append(
                {
                    "id": f"H{hunk_number:03d}",
                    "old_start": int(values["old"]),
                    "old_count": int(values["old_count"] or "1"),
                    "new_start": int(values["new"]),
                    "new_count": int(values["new_count"] or "1"),
                    "context": values["context"].strip(),
                }
            )
    if file_index != len(files):
        raise RuntimeError(
            f"diff file count mismatch: text={file_index}, raw={len(files)}"
        )


def write_manifest(
    path: Path,
    *,
    repo: Path,
    base: str,
    base_commit: str,
    comparison_mode: str,
    comparison_commit: str,
    files: list[FileDiff],
) -> None:
    hunk_count = sum(len(item.hunks) for item in files)
    lines = [
        "# Self-review hunk manifest",
        "",
        f"- Repository: `{repo}`",
        f"- Base: `{base}` (`{base_commit}`)",
        f"- Comparison: `{comparison_mode}` from `{comparison_commit}`",
        f"- Files: {len(files)}",
        f"- Hunks: {hunk_count}",
        "",
    ]
    for item in files:
        rename = f" from `{item.old_path}`" if item.old_path else ""
        sources = ", ".join(item.sources) if item.sources else "snapshot-only"
        lines.extend(
            [
                f"## **{item.change_id}**: `{item.path}` ({item.status}{rename})",
                "",
                f"- Provenance layers: {sources}",
            ]
        )
        if not item.hunks:
            lines.extend(
                [
                    "- No textual hunk: account for this file-level change "
                    "(binary, empty, mode, rename/copy, submodule, or metadata).",
                    "",
                ]
            )
            continue
        for hunk in item.hunks:
            old_end = hunk["old_start"] + max(hunk["old_count"] - 1, 0)
            new_end = hunk["new_start"] + max(hunk["new_count"] - 1, 0)
            context = f" — {hunk['context']}" if hunk["context"] else ""
            lines.append(
                f"- **{hunk['id']}**: old {hunk['old_start']}-{old_end}, "
                f"new {hunk['new_start']}-{new_end}{context}"
            )
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def render_html(diff_path: Path, html_path: Path, title: str) -> None:
    command = [
        "npx",
        "-y",
        f"diff2html-cli@{DIFF2HTML_VERSION}",
        "-i",
        "file",
        "-s",
        "side",
        "--summary",
        "open",
        "--colorScheme",
        "light",
        "-F",
        str(html_path),
        "-t",
        title,
        "--",
        str(diff_path),
    ]
    result = run(command, cwd=diff_path.parent, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            "diff2html rendering failed:\n"
            f"{result.stdout}\n{result.stderr}\n"
            f"Command: {shlex.join(command)}"
        )
    if not html_path.is_file() or html_path.stat().st_size == 0:
        raise RuntimeError("diff2html reported success but produced no HTML")


def merge_state(repo: Path) -> str:
    git_dir = Path(git(repo, "rev-parse", "--absolute-git-dir").strip())
    if (git_dir / "MERGE_HEAD").exists():
        return "merge"
    if (git_dir / "rebase-merge").exists() or (git_dir / "rebase-apply").exists():
        return "rebase"
    if (git_dir / "CHERRY_PICK_HEAD").exists():
        return "cherry-pick"
    if (git_dir / "REVERT_HEAD").exists():
        return "revert"
    if (git_dir / "BISECT_LOG").exists():
        return "bisect"
    if (git_dir / "sequencer").exists():
        return "sequencer"
    return "none"


def build(args: argparse.Namespace) -> int:
    repo = repo_root(args.repo.resolve())
    output = args.output.resolve() if args.output else default_output(repo)
    output_rel = relative_output(repo, output)
    base_commit = git(repo, "rev-parse", f"{args.base}^{{commit}}").strip()
    head_commit = git(repo, "rev-parse", "HEAD").strip()
    branch = git(repo, "branch", "--show-current").strip() or "(detached)"
    state_before = merge_state(repo)
    merge_heads_before = merge_heads(repo)
    status_before = status_bytes(repo, output_rel)
    if run(["git", "ls-files", "-u"], cwd=repo).stdout:
        raise RuntimeError("unresolved index entries remain; resolve conflicts first")

    snapshot = snapshot_tree(repo, output_rel)
    before, comparison_mode = comparison_commit(
        repo,
        base_commit=base_commit,
        head_commit=head_commit,
        mode=args.comparison,
    )
    diff = local_diff(repo, before, snapshot)
    files = raw_file_records(repo, before, snapshot)
    attach_hunks(diff, files)
    provenance_data = provenance(
        repo,
        base_commit=base_commit,
        head_commit=head_commit,
        status_raw=status_before,
    )
    apply_sources(files, provenance_data)
    hunk_count = sum(len(item.hunks) for item in files)
    status_counts = porcelain_record_types(status_before)

    git_dir = Path(git(repo, "rev-parse", "--absolute-git-dir").strip())
    temp_parent = git_dir / "self-review-tmp"
    temp_parent.mkdir(parents=True, exist_ok=True)
    temp_dir = Path(tempfile.mkdtemp(prefix="build-", dir=temp_parent))
    try:
        diff_path = temp_dir / "files-changed.diff"
        html_path = temp_dir / "files-changed.html"
        manifest_path = temp_dir / "hunk-manifest.md"
        provenance_path = temp_dir / "provenance.json"
        metadata_path = temp_dir / "metadata.json"

        diff_path.write_text(diff, encoding="utf-8", errors="surrogateescape")
        write_manifest(
            manifest_path,
            repo=repo,
            base=args.base,
            base_commit=base_commit,
            comparison_mode=comparison_mode,
            comparison_commit=before,
            files=files,
        )
        provenance_path.write_text(
            json.dumps(provenance_data, indent=2) + "\n",
            encoding="utf-8",
        )
        render_html(
            diff_path,
            html_path,
            args.title or f"Self review: {branch} against {args.base}",
        )

        metadata = {
            "generated_at": dt.datetime.now(dt.UTC).isoformat(),
            "repository": str(repo),
            "branch": branch,
            "head_commit": head_commit,
            "base_ref": args.base,
            "base_commit": base_commit,
            "comparison_mode": comparison_mode,
            "comparison_commit": before,
            "snapshot_tree": snapshot,
            "operation_state": state_before,
            "merge_heads": merge_heads_before,
            "status": {
                "record_count": sum(status_counts.values()),
                "counts_by_record_type": dict(sorted(status_counts.items())),
                "porcelain_v2_z_sha256": hashlib.sha256(status_before).hexdigest(),
            },
            "file_count": len(files),
            "hunk_count": hunk_count,
            "change_ids": [item.change_id for item in files],
            "hunk_ids": [hunk["id"] for item in files for hunk in item.hunks],
            "renderer": f"diff2html-cli@{DIFF2HTML_VERSION}",
            "artifacts": {
                "diff": str(output / "files-changed.diff"),
                "html": str(output / "files-changed.html"),
                "manifest": str(output / "hunk-manifest.md"),
                "provenance": str(output / "provenance.json"),
            },
        }
        for artifact in (diff_path, html_path, manifest_path, provenance_path):
            metadata[f"{artifact.name}_sha256"] = hashlib.sha256(
                artifact.read_bytes()
            ).hexdigest()
        metadata_path.write_text(
            json.dumps(metadata, indent=2) + "\n",
            encoding="utf-8",
        )

        manifest_text = manifest_path.read_text(encoding="utf-8")
        if any(manifest_text.count(f"**{item.change_id}**") != 1 for item in files):
            raise RuntimeError("artifact verification failed: change ID mismatch")
        if any(
            manifest_text.count(f"**{hunk['id']}**") != 1
            for item in files
            for hunk in item.hunks
        ):
            raise RuntimeError("artifact verification failed: hunk ID mismatch")
        html_text = html_path.read_text(encoding="utf-8")
        if "d2h-file-wrapper" not in html_text and files:
            raise RuntimeError("artifact verification failed: HTML has no file diff")

        if git(repo, "rev-parse", "HEAD").strip() != head_commit:
            raise RuntimeError("HEAD changed while building review artifacts")
        if merge_state(repo) != state_before or merge_heads(repo) != merge_heads_before:
            raise RuntimeError("Git operation state changed while building artifacts")
        if snapshot_tree(repo, output_rel) != snapshot:
            raise RuntimeError("working tree changed while building review artifacts")
        if status_bytes(repo, output_rel) != status_before:
            raise RuntimeError("Git status changed while building review artifacts")

        output.parent.mkdir(parents=True, exist_ok=True)
        backup = output.with_name(f".{output.name}.previous")
        if backup.exists():
            shutil.rmtree(backup)
        if output.exists():
            os.replace(output, backup)
        try:
            try:
                os.replace(temp_dir, output)
            except OSError:
                shutil.copytree(temp_dir, output)
                shutil.rmtree(temp_dir)
        except Exception:
            if backup.exists() and not output.exists():
                os.replace(backup, output)
            raise
        if backup.exists():
            shutil.rmtree(backup)

        print(json.dumps(metadata, indent=2))
    finally:
        if temp_dir.exists():
            shutil.rmtree(temp_dir)
    return 0


def serve(directory: Path, host: str, requested_port: int) -> int:
    directory = directory.resolve()
    if host not in {"127.0.0.1", "localhost", "::1"}:
        raise RuntimeError("refusing to expose review artifacts beyond loopback")
    html = directory / "files-changed.html"
    if not html.is_file():
        raise FileNotFoundError(f"missing preview: {html}")
    handler = functools.partial(
        http.server.SimpleHTTPRequestHandler,
        directory=str(directory),
    )
    server = None
    for port in range(requested_port, requested_port + 20):
        try:
            server = http.server.ThreadingHTTPServer((host, port), handler)
            break
        except OSError:
            continue
    if server is None:
        raise OSError(f"no free port in {requested_port}..{requested_port + 19}")
    cache_key = hashlib.sha256(html.read_bytes()).hexdigest()[:12]
    print(
        f"http://{host}:{server.server_port}/files-changed.html?v={cache_key}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo", type=Path, default=Path.cwd())
    result.add_argument("--base", help="base ref for the local feature diff")
    result.add_argument(
        "--comparison",
        choices=("auto", "merge-base", "base"),
        default="auto",
        help="auto uses base for an in-progress merge of that base, else merge-base",
    )
    result.add_argument("--output", type=Path)
    result.add_argument("--title")
    result.add_argument("--serve", type=Path, metavar="ARTIFACT_DIR")
    result.add_argument("--host", default="127.0.0.1")
    result.add_argument("--port", type=int, default=8766)
    return result


def main() -> int:
    args = parser().parse_args()
    if args.serve:
        return serve(args.serve, args.host, args.port)
    if not args.base:
        parser().error("--base is required when building artifacts")
    return build(args)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
