---
name: git-worktrees
description: Conventions for where git repos live on this machine and how to check them out for task-specific work. Canonical clones live in ~/apps; work on a specific task happens in a git worktree created in the local working directory. Use when cloning a repo, checking out a branch for a task, creating or removing a git worktree, or deciding where a repo should live on disk.
---

# Git Worktrees

## Policy

- The default location for git repos is `~/apps`. Each repo is cloned there once (e.g. `~/apps/aiter`).
- When working on something specific, use a git worktree in the local directory instead of a fresh clone.
- This keeps a single git history per repo on the device, and repos stay centralized in `~/apps`.

## Workflow

1. **Ensure the canonical clone exists in `~/apps`.**

   ```bash
   REPO=aiter
   [ -d ~/apps/$REPO ] || git clone git@github.com:ROCm/$REPO.git ~/apps/$REPO
   git -C ~/apps/$REPO fetch --all --prune
   ```

2. **Create a worktree in the local (task) directory.** Name the branch after the task.

   ```bash
   # New branch off the up-to-date default branch
   git -C ~/apps/$REPO worktree add "$PWD/$REPO" -b <task-branch> origin/main

   # Or check out an existing remote branch / PR branch
   git -C ~/apps/$REPO worktree add "$PWD/$REPO" <existing-branch>
   ```

3. **Work in the worktree as normal.** Commits, pushes, and branches are shared with `~/apps/$REPO` because they use the same `.git` store.

4. **Clean up when the task is done.**

   ```bash
   git -C ~/apps/$REPO worktree remove "$PWD/$REPO"
   git -C ~/apps/$REPO worktree prune
   ```

## Rules

- Do not `git clone` a repo into a task directory if it already exists (or should exist) in `~/apps`; add a worktree instead.
- Leave the `~/apps/<repo>` checkout on its default branch; do task work in worktrees.
- A branch can only be checked out in one worktree at a time. If `worktree add` fails for that reason, run `git -C ~/apps/<repo> worktree list` to find where it is checked out.
- Git submodules are not shared between worktrees; run `git submodule update --init --recursive` inside each new worktree that needs them.
- Before deleting a task directory, remove its worktrees (or run `worktree prune` afterwards) so `~/apps/<repo>` does not keep stale entries.
