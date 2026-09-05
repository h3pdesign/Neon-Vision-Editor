# Automatic branch cleanup

GitHub owns remote cleanup: enable **Automatically delete head branches** after PR merge. Deletion rules protect `main`, `develop`, and `archive/*`. Do not add an age-based remote branch sweeper. The recurring metrics workflow may recreate its own branch.

Local cleanup uses Python 3.9+ and authenticated `git`/`gh`. Run from a clean repository root:

```sh
python3 scripts/cleanup_branches.py --repo "$PWD" --github-repo h3pdesign/Neon-Vision-Editor --dry-run
```

Use `--apply` for deletion. `--apply --not-before 2026-09-12T09:14:22+00:00` stays report-only until that instant. The scheduled task uses this one-week grace period and runs weekly through Codex; it is not a launchd service and depends on the local Codex automation environment being available.

Only branches with a missing origin upstream, no open PR reference, no checked-out worktree, and a tip reachable from freshly fetched `origin/main` or `origin/develop` qualify. Local-only branches, unique commits, and squash/rebase cases without ancestry proof require manual review. Git's own `branch -d` refusal is never overridden. The script does not switch branches, stash changes, delete remote branches, or remove worktree files.

Always preserved: `main`, `develop`, `archive/*`, `release/*`, `automation/*`, `codex/backup-*`, and `codex/macos-27-agentic-editor`. Update this list deliberately when long-lived development branches change.

Fetch/authentication errors and a dirty current worktree abort cleanup. A shared lock prevents overlapping cleanup runs. Audit entries containing time, branch, original tip, action, and reason are appended to `branch-cleanup.jsonl` in the shared Git directory. Commits on deleted branches remain reachable from the integration branch; restore a name with `git branch <name> <logged-tip>`.

The scheduled command should load the script from a pinned reviewed commit with `git show <commit>:scripts/cleanup_branches.py`, not execute an arbitrary version from the current checkout. Update that pinned commit only after tests and review. Pause/delete the automation in Codex to disable scheduling; `git config --local fetch.prune false` disables automatic remote-reference pruning.

Tests: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_cleanup_branches.py`.
