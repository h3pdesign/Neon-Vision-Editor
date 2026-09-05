import unittest
import argparse
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch
from datetime import datetime, timezone
from cleanup_branches import apply_enabled, skip_reason, cleanup


class CleanupPolicyTests(unittest.TestCase):
    def reason(self, name="codex/done", upstream="refs/remotes/origin/codex/done",
               in_use=(), prs=(), heads=(), merged=True):
        return skip_reason(name, upstream, set(in_use), set(prs), set(heads), merged)

    def test_only_merged_deleted_remote_candidate(self):
        self.assertIsNone(self.reason())

    def test_preserved_names(self):
        for name in ("main", "develop", "archive/old/nested", "release/1.7",
                     "automation/daily-metrics", "codex/backup-save", "codex/macos-27-agentic-editor"):
            with self.subTest(name=name):
                self.assertEqual(self.reason(name=name), "preserved")

    def test_worktree_is_never_detached(self):
        self.assertIsNotNone(self.reason(in_use=["codex/done"]))

    def test_pr_head_or_base_protects_branch(self):
        self.assertIsNotNone(self.reason(prs=["codex/done"]))

    def test_differently_named_upstream_is_checked(self):
        self.assertIsNotNone(self.reason(upstream="refs/remotes/origin/remote-name", prs=["remote-name"]))
        self.assertIsNotNone(self.reason(upstream="refs/remotes/origin/remote-name", heads=["remote-name"]))

    def test_unpublished_and_other_remote_branches_require_manual_review(self):
        self.assertIsNotNone(self.reason(upstream=""))
        self.assertIsNotNone(self.reason(upstream="refs/remotes/upstream/codex/done"))

    def test_live_remote_is_not_deleted(self):
        self.assertIsNotNone(self.reason(heads=["codex/done"]))

    def test_squashed_or_unique_commits_are_preserved(self):
        self.assertIsNotNone(self.reason(merged=False))

    def test_report_only_and_grace_period(self):
        cutoff = datetime(2026, 9, 12, tzinfo=timezone.utc)
        before = datetime(2026, 9, 5, tzinfo=timezone.utc)
        self.assertFalse(apply_enabled(False, None, cutoff))
        self.assertFalse(apply_enabled(True, cutoff, before))
        self.assertTrue(apply_enabled(True, cutoff, cutoff))
        self.assertTrue(apply_enabled(True, None, before))

    def test_naive_cutoff_rejected(self):
        with self.assertRaises(ValueError):
            apply_enabled(True, datetime(2026, 9, 12), datetime.now(timezone.utc))

    def simulate(self, apply=False, failure=None, dirty=False, changed=False, refusal=False):
        with tempfile.TemporaryDirectory() as directory:
            calls = []
            repo = Path(directory).resolve()
            common = repo / ".git"
            common.mkdir()
            def command(*args, cwd):
                calls.append(args)
                if failure and args[:2] == failure:
                    raise subprocess.CalledProcessError(1, args)
                if args[0] == "gh":
                    return "[[]]"
                key = args[1:]
                if key == ("rev-parse", "--show-toplevel"): return str(repo)
                if key == ("remote", "get-url", "origin"): return "https://github.com/example/repo.git"
                if key == ("rev-parse", "--git-common-dir"): return str(common)
                if key[0] == "status": return " M changed" if dirty else ""
                if key[0] == "fetch": return ""
                if key[:2] == ("rev-parse", "--verify"): return "base"
                if key[0] == "ls-remote": return ""
                if key[0] == "worktree": return "branch refs/heads/develop"
                if key[0] == "for-each-ref": return "codex/done\ttip\trefs/remotes/origin/codex/done"
                if key[0] == "rev-parse": return "new-tip" if changed else "tip"
                if key[:2] == ("branch", "-d"):
                    if refusal: raise subprocess.CalledProcessError(1, args)
                    return "Deleted"
                raise AssertionError(args)
            args = argparse.Namespace(repo=str(repo), github_repo="example/repo", apply=apply, not_before=None)
            with patch("cleanup_branches.run", side_effect=command), patch("cleanup_branches.subprocess.run", return_value=subprocess.CompletedProcess([], 0)):
                cleanup(args)
            return calls, (common / "branch-cleanup.jsonl").read_text()

    def test_dry_run_never_calls_delete(self):
        calls, audit = self.simulate()
        self.assertFalse(any(call[:3] == ("git", "branch", "-d") for call in calls))
        self.assertIn('"action": "candidate"', audit)

    def test_apply_uses_nonforced_delete_and_logs_tip(self):
        calls, audit = self.simulate(apply=True)
        self.assertIn(("git", "branch", "-d", "--", "codex/done"), calls)
        self.assertIn('"action": "deleted"', audit)
        self.assertIn('"tip": "tip"', audit)

    def test_tip_race_prevents_deletion(self):
        calls, audit = self.simulate(apply=True, changed=True)
        self.assertFalse(any(call[:3] == ("git", "branch", "-d") for call in calls))
        self.assertIn("branch changed", audit)

    def test_git_refusal_is_not_force_retried(self):
        calls, audit = self.simulate(apply=True, refusal=True)
        self.assertIn("refused", audit)
        self.assertFalse(any("-D" in call for call in calls))

    def test_dirty_worktree_or_network_failure_aborts(self):
        with self.assertRaises(ValueError): self.simulate(apply=True, dirty=True)
        for failure in (("git", "fetch"), ("gh", "api")):
            with self.subTest(failure=failure), self.assertRaises(subprocess.CalledProcessError):
                self.simulate(apply=True, failure=failure)


if __name__ == "__main__":
    unittest.main()
