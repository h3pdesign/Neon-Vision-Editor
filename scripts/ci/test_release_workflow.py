#!/usr/bin/env python3
"""Offline regression suite for release preparation; never builds or publishes."""
import base64
import copy
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "scripts"))


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


docs = load("release_docs", "scripts/prepare_release_docs.py")
prep = load("release_prepare", "scripts/release_prepare.py")
public = load("public_release", "scripts/ci/wait_for_public_release.py")
cloud_module = load("cloud_counter", "scripts/cloud_build_number.py")


def fixture(root):
    inputs = [".gitignore", "README.md", "CHANGELOG.md", "ARCHITECTURE.md", prep.PROJECT,
              "Neon Vision Editor/UI/PanelsAndHelpers.swift", "site/index.html", "site/changelog.html",
              *(f"site/{locale}/index.html" for locale in docs.LOCALIZED_WEBSITES),
              "scripts/prepare_release_docs.py", "scripts/release_prepare.py", "scripts/release_prep.sh", "scripts/release_all.sh", "scripts/cloud_build_number.py",
              "scripts/extract_changelog_section.sh", "scripts/ci/release_milestone_preflight.sh",
              "scripts/ci/release_notes_quality_gate.sh", "scripts/ci/validate_release_metadata.sh"]
    for name in inputs:
        (root / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, root / name)
    (root / "release").mkdir()
    readme = root / "README.md"
    readme.write_text(re.sub(r"(?m)^> Latest release: \*\*v[^*]+\*\*$", "> Latest release: **v1.6.1**", readme.read_text()))


class ReleaseWorkflowTests(unittest.TestCase):
    def test_ref_inventory_accepts_no_named_refs(self):
        with tempfile.TemporaryDirectory(prefix="nve-empty-refs-") as temp:
            root = Path(temp)
            prep.run("git", "init", "-q", cwd=root)
            self.assertEqual("", prep.git("for-each-ref", "--format=%(refname) %(objectname)", cwd=root))

    def test_promoted_unreleased_stays_above_release(self):
        content = "# Changelog\n\n## [Unreleased]\n\n### Highlights\n\n- A real fix.\n\n## [v1.6.1] - 2026-09-04\n"
        result = docs.promote_unreleased_section(content, "v1.6.2", "2026-09-05")
        self.assertLess(result.index("## [Unreleased]"), result.index("## [v1.6.2]"))
        self.assertEqual(result.count("- A real fix."), 1)

    def test_empty_unreleased_is_not_release_content(self):
        self.assertIsNone(docs.promote_unreleased_section("## [Unreleased]\n\n", "v1.6.2", "2026-09-05"))

    def test_public_history_excludes_future_release_links(self):
        original = (ROOT / "CHANGELOG.md").read_text()
        content = original if docs.has_changelog_section(original, "v1.6.2") else docs.promote_unreleased_section(original, "v1.6.2", "2026-09-05")
        result = docs.public_changelog(content, "v1.6.1")
        self.assertNotIn("## [v1.6.2]", result)
        self.assertIn("## [v1.6.1]", result)

    def test_mixed_build_numbers_fail_closed(self):
        for text in ("", "CURRENT_PROJECT_VERSION = 1;\nCURRENT_PROJECT_VERSION = 2;"):
            with self.assertRaises(ValueError):
                prep.project_build(text)

    def test_malformed_release_allocation_is_rejected(self):
        valid = dict(tag="v1.6.2", source="a" * 40, date="2026-09-05", build=1018,
                     published_tag="v1.6.1", published_build=1017, status="prepared")
        prep.validate_state(valid)
        for key, value in (("build", True), ("build", 1017), ("source", "main"),
                           ("tag", "v1.6.1"), ("date", "2026-99-99"), ("status", "unknown")):
            state = dict(valid, **{key: value})
            with self.assertRaises(ValueError):
                prep.validate_state(state)

    def test_dry_run_never_calls_remote_or_mutating_git_commands(self):
        # Both public entry points share this offline path. Block gh entirely and
        # allow only the Git queries used to snapshot the selected checkout.
        with tempfile.TemporaryDirectory(prefix="nve-dry-guard-") as temp:
            directory = Path(temp)
            root = directory / "fixture"
            fixture(root)
            paths = directory / "paths"
            paths.write_bytes(b"\0".join(str(p.relative_to(root)).encode() for p in root.rglob("*") if p.is_file()) + b"\0")
            # Supply an immutable fixture snapshot, not the changing host tags.
            git_wrapper = directory / "git"
            git_wrapper.write_text('#!/bin/sh\ncase "$1" in\ntag) exit 0;;\nrev-parse) echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;;\nls-files) if [ "$2" != "--others" ]; then cat "' + str(paths) + '"; fi;;\nshow) cat "' + str(root / prep.PROJECT) + '";;\n*) echo "Forbidden Git command in dry run: $*" >&2; exit 99;;\nesac\n')
            git_wrapper.chmod(0o755)
            gh_wrapper = directory / "gh"
            gh_wrapper.write_text('#!/bin/sh\necho "Forbidden GitHub call in dry run" >&2\nexit 99\n')
            gh_wrapper.chmod(0o755)
            before = (prep.git("status", "--porcelain"), prep.git("for-each-ref", "--format=%(refname) %(objectname)"), prep.git("branch", "--show-current"))
            fixture_before = prep.snapshot(root)
            env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["bash", "scripts/release_all.sh", "v1.6.2", "--dry-run"],
                                    cwd=root, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS:", result.stdout)
            self.assertEqual(fixture_before, prep.snapshot(root))
            self.assertEqual(before, (prep.git("status", "--porcelain"), prep.git("for-each-ref", "--format=%(refname) %(objectname)"), prep.git("branch", "--show-current")))

    def test_generation_is_repeatable_and_publication_is_separate(self):
        with tempfile.TemporaryDirectory(prefix="nve-docs-test-") as temp:
            root = Path(temp)
            fixture(root)
            state = dict(tag="v1.6.2", source="a" * 40, date="2026-09-05", build=1018,
                         published_tag="v1.6.1", published_build=1017, status="prepared")
            with mock.patch.dict(os.environ, NVE_RELEASE_OFFLINE="1"):
                prep.prepare_files(root, state)
                first = prep.snapshot(root)
                prep.prepare_files(root, state)
                self.assertEqual(first, prep.snapshot(root))
            for name in ["README.md", "site/index.html", "site/changelog.html",
                         *(f"site/{locale}/index.html" for locale in docs.LOCALIZED_WEBSITES)]:
                self.assertNotIn("releases/tag/v1.6.2", (root / name).read_text(), name)
            self.assertIn("Prepared release: **v1.6.2**", (root / "README.md").read_text())
            self.assertIn("What’s New in v1.6.2", (root / "Neon Vision Editor/UI/PanelsAndHelpers.swift").read_text())
            self.assertEqual(prep.project_build((root / prep.PROJECT).read_text()), 1018)
            prep.run("python3", "scripts/prepare_release_docs.py", "v1.6.2", "--published", cwd=root)
            prep.run("python3", "scripts/prepare_release_docs.py", "v1.6.2", "--check", cwd=root)
            self.assertNotIn("Prepared release:", (root / "README.md").read_text())
            self.assertIn("releases/tag/v1.6.2", (root / "site/index.html").read_text())
            self.assertEqual(json.loads((root / prep.STATE).read_text())["status"], "published")
            self.assertEqual(prep.project_build((root / prep.PROJECT).read_text()), 1018)

    def test_readiness_requires_matching_stable_release_and_uploaded_assets(self):
        release = dict(tag_name="v1.6.2", draft=False, prerelease=False, published_at="2026-09-05",
                       assets=[dict(name=n, size=1, state="uploaded") for n in public.ASSETS])
        self.assertTrue(public.ready(release, "v1.6.2"))
        for key, value in (("draft", True), ("prerelease", True), ("published_at", None), ("assets", [])):
            bad = copy.deepcopy(release)
            bad[key] = value
            self.assertFalse(public.ready(bad, "v1.6.2"))
        self.assertFalse(public.ready(release, "v1.6.3"))

    def test_checksums_reject_corruption_and_unexpected_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in public.ASSETS - {"SHA256SUMS.txt"}:
                (root / name).write_bytes(b"test artifact")
            digest = hashlib.sha256(b"test artifact").hexdigest()
            valid = "".join(f"{digest}  {name}\n" for name in sorted(public.ASSETS - {"SHA256SUMS.txt"}))
            (root / "SHA256SUMS.txt").write_text(valid)
            public.verify_checksums(root)
            for bad in (valid.replace(digest, "0" * 64), valid + f"{digest}  ../escape\n", valid + valid):
                (root / "SHA256SUMS.txt").write_text(bad)
                with self.assertRaises(ValueError):
                    public.verify_checksums(root)

    def test_dry_run_rejects_mutating_combinations(self):
        for args in (["scripts/release_prep.sh", "v1.6.2", "--dry-run", "--push"],
                     ["scripts/release_all.sh", "v1.6.2", "--dry-run", "--retag"],
                     ["scripts/release_all.sh", "v1.6.2", "--dry-run", "--replace-assets-from-app", "/nonexistent"]):
            result = subprocess.run(["bash", *args], cwd=ROOT, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_dispatch_pins_sha_and_documentation_writers_queue(self):
        hosted = (ROOT / ".github/workflows/release-github-only.yml").read_text()
        checkout = hosted.split("- name: Checkout release source", 1)[1].split("- name: Validate release docs", 1)[0]
        self.assertNotIn("--depth=1", checkout)
        self.assertIn('merge-base --is-ancestor "$SOURCE_SHA" "$MAIN_SHA"', checkout)
        self.assertIn('-f ref="$RELEASE_SHA"', (ROOT / "scripts/release_all.sh").read_text())
        self.assertNotIn('-f ref=main', (ROOT / "scripts/release_all.sh").read_text())
        for name in ("post-release-documentation-sync", "sync-readme-appstore-versions", "update-download-metrics"):
            workflow = (ROOT / f".github/workflows/{name}.yml").read_text()
            self.assertIn("group: public-documentation-writer", workflow)
            self.assertIn("queue: max", workflow)
            self.assertNotIn("run: sleep", workflow)

    @unittest.skipUnless(shutil.which("ssh-keygen"), "SSH signing executable unavailable")
    def test_real_local_worktree_signing_resume_and_source_preservation(self):
        # Only disposable repositories and a disposable SSH key are used.
        # gh is a stub; origin is a local bare repository, not GitHub.
        with tempfile.TemporaryDirectory(prefix="nve-release-integration-") as temp:
            base = Path(temp)
            root = base / "repo"
            root.mkdir()
            fixture(root)
            key = base / "test-key"
            # The network boundary is independently tested below. This subprocess
            # fixture exercises real Git/signing without accessing Apple services.
            (root / "scripts/cloud_build_number.py").write_text('import os\nclass CloudBuildCounter:\n    @classmethod\n    def from_environment(cls): return cls()\n    def snapshot(self): return {"product_id": "fixture", "max_number": int(os.environ.get("NVE_TEST_CLOUD_NUMBER", "1040"))}\n    def assert_unchanged(self, expected, candidate):\n        if expected != self.snapshot() or candidate <= self.snapshot()["max_number"]: raise ValueError("Cloud changed")\n')
            prep.run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key))
            signers = base / "allowed-signers"
            signers.write_text("release-test@example.invalid " + key.with_suffix(".pub").read_text())
            prep.run("git", "init", "-q", "-b", "develop", cwd=root)
            for name, value in {"user.name": "Release Test", "user.email": "release-test@example.invalid",
                                "gpg.format": "ssh", "user.signingkey": str(key),
                                "gpg.ssh.allowedSignersFile": str(signers), "core.hooksPath": "/dev/null",
                                "core.autocrlf": "false"}.items():
                prep.run("git", "config", name, value, cwd=root)
            prep.run("git", "add", "--all", cwd=root)
            prep.run("git", "commit", "-q", "-S", "-m", "Fixture baseline", cwd=root)
            prep.run("git", "tag", "v1.6.1", cwd=root)
            origin = base / "origin.git"
            prep.run("git", "init", "--bare", "-q", str(origin))
            prep.run("git", "remote", "add", "origin", str(origin), cwd=root)
            prep.run("git", "push", "-q", "origin", "develop", "--tags", cwd=root)
            fakebin = base / "bin"
            fakebin.mkdir()
            fake = fakebin / "gh"
            fake.write_text('#!/bin/sh\ncase "$1" in\napi) printf "1\\t${NVE_TEST_MILESTONE_STATE:-open}\\n";;\nissue) echo "[]";;\n*) exit 97;;\nesac\n')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(fakebin) + os.pathsep + os.environ["PATH"])
            before = prep.git("rev-parse", "HEAD", cwd=root)
            command = [sys.executable, "scripts/release_prepare.py", "v1.6.2", "--date", "2026-09-05"]
            blocked = subprocess.run(command, cwd=root, env=env, text=True, capture_output=True)
            self.assertNotEqual(blocked.returncode, 0)
            release = base / "repo-release-1.6.2"
            self.assertTrue((release / prep.STATE).exists(), blocked.stdout + blocked.stderr)
            allocated = json.loads((release / prep.STATE).read_text())
            self.assertGreaterEqual(allocated["build"], 1041)
            env["NVE_TEST_MILESTONE_STATE"] = "closed"
            resumed = subprocess.run(command + ["--resume"], cwd=root, env=env, text=True, capture_output=True)
            self.assertEqual(resumed.returncode, 0, resumed.stdout + resumed.stderr)
            release_sha = prep.git("rev-parse", "HEAD", cwd=release)
            repeated = subprocess.run(command, cwd=root, env=env, text=True, capture_output=True)
            self.assertEqual(repeated.returncode, 0, repeated.stdout + repeated.stderr)
            self.assertEqual(release_sha, prep.git("rev-parse", "HEAD", cwd=release))
            self.assertEqual(allocated, json.loads((release / prep.STATE).read_text()))
            self.assertEqual(before, prep.git("rev-parse", "HEAD", cwd=root))
            self.assertEqual("develop", prep.git("branch", "--show-current", cwd=root))
            self.assertEqual("", prep.git("status", "--porcelain", cwd=root))
            self.assertEqual("", prep.git("ls-remote", "--heads", "origin", "refs/heads/release/1.6.2", cwd=root))
            env["NVE_TEST_CLOUD_NUMBER"] = str(allocated["build"])
            stale = subprocess.run(command, cwd=root, env=env, text=True, capture_output=True)
            self.assertNotEqual(stale.returncode, 0)
            self.assertEqual(release_sha, prep.git("rev-parse", "HEAD", cwd=release))
            env.pop("NVE_TEST_CLOUD_NUMBER")
            (release / "unrelated.txt").write_text("preserve me")
            rejected = subprocess.run(command + ["--resume"], cwd=root, env=env, text=True, capture_output=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual("preserve me", (release / "unrelated.txt").read_text())


class CloudCounterTests(unittest.TestCase):
    def setUp(self):
        config = mock.patch.object(cloud_module, "local_setting", return_value="")
        config.start()
        self.addCleanup(config.stop)
        self.client = cloud_module.CloudBuildCounter("product-id", "fixture-token")

    @staticmethod
    def page(number=1028, progress="COMPLETE", next_url=None):
        return {"data": [{"type": "ciBuildRuns", "id": str(number),
                          "attributes": {"number": number, "executionProgress": progress}}],
                "links": {"next": next_url}}

    def test_all_pages_contribute_to_maximum(self):
        next_url = cloud_module.ORIGIN + "/v1/ciProducts/product-id/buildRuns?cursor=older"
        with mock.patch.object(self.client, "_get", side_effect=[self.page(1028, next_url=next_url), self.page(1032)]):
            self.assertEqual(self.client.snapshot(), {"product_id": "product-id", "max_number": 1032})

    def test_running_pending_and_unknown_states_block(self):
        for progress in ("PENDING", "RUNNING", None, "OTHER"):
            with self.subTest(progress=progress), mock.patch.object(self.client, "_get", return_value=self.page(progress=progress)):
                with self.assertRaisesRegex(ValueError, "active, queued or unknown"):
                    self.client.snapshot()

    def test_old_testflight_distribution_does_not_block_counter(self):
        history = self.page(1028)
        history['data'] += self.page(968, 'RUNNING')['data']
        actions = {'data': [
            {'id': 'archive', 'type': 'ciBuildActions', 'attributes': {
                'actionType': 'ARCHIVE', 'name': 'Archive - macOS',
                'executionProgress': 'COMPLETE', 'completionStatus': 'SUCCEEDED',
                'finishedDate': '2026-08-05T23:44:16Z'}},
            {'id': 'distribution', 'type': 'ciBuildActions', 'attributes': {
                'actionType': 'TEST', 'name': 'TestFlight External Testing - macOS',
                'executionProgress': 'RUNNING', 'completionStatus': None,
                'startedDate': '2026-08-05T23:48:01Z', 'finishedDate': None}}
        ], 'links': {}}
        actions['data'].append({'id': 'notarize', 'type': 'ciBuildActions', 'attributes': {
            'actionType': 'ARCHIVE', 'name': 'Notarize - macOS',
            'executionProgress': 'COMPLETE', 'completionStatus': 'SUCCEEDED',
            'finishedDate': '2026-08-05T23:49:04Z'}})
        with mock.patch.object(self.client, '_get', side_effect=[history, actions]):
            self.assertEqual(self.client.snapshot()['max_number'], 1028)

        next_url = cloud_module.ORIGIN + '/v1/ciBuildRuns/968/actions?cursor=next'
        first = {'data': actions['data'][:1], 'links': {'next': next_url}}
        second = {'data': actions['data'][1:], 'links': {}}
        with mock.patch.object(self.client, '_get', side_effect=[history, first, second]) as get:
            self.assertEqual(self.client.snapshot()['max_number'], 1028)
            self.assertEqual(get.call_args.kwargs, {'action_run_id': '968'})
        for bad in ({'data': actions['data'], 'links': {'next': next_url}},
                    {'data': None, 'links': {}}, {'data': actions['data'], 'links': {'next': 42}},
                    {'data': actions['data'], 'links': {'next': ''}}):
            with mock.patch.object(self.client, '_get', side_effect=[history, first, bad]):
                with self.assertRaises(ValueError):
                    self.client.snapshot()

        failed_archive = copy.deepcopy(actions)
        failed_archive['data'][0]['attributes']['completionStatus'] = 'FAILED'
        with mock.patch.object(self.client, '_get', side_effect=[history, failed_archive]):
            with self.assertRaises(ValueError):
                self.client.snapshot()

        with mock.patch.object(self.client, '_get') as get:
            self.assertFalse(self.client._only_lingering_distribution('968', 0))
            get.assert_not_called()

        for field, value in [('name', 'Unit tests'), ('actionType', 'BUILD'),
                             ('executionProgress', 'PENDING'), ('startedDate', None),
                             ('startedDate', '2026-08-05T23:40:00Z')]:
            bad = copy.deepcopy(actions)
            bad['data'][1]['attributes'][field] = value
            with self.subTest(field=field, value=value), mock.patch.object(self.client, '_get', side_effect=[history, bad]):
                with self.assertRaises(ValueError):
                    self.client.snapshot()

        for records in ([], actions['data'][1:], [dict(actions['data'][0], attributes={})]):
            with mock.patch.object(self.client, '_get', side_effect=[history, {'data': records, 'links': {}}]):
                with self.assertRaises(ValueError):
                    self.client.snapshot()

        latest_running = self.page(1029, 'RUNNING')
        latest_running['data'] += self.page(1028)['data']
        with mock.patch.object(self.client, '_get', return_value=latest_running) as get:
            with self.assertRaises(ValueError):
                self.client.snapshot()
            self.assertEqual(get.call_count, 1)

    def test_empty_malformed_and_duplicate_history_block(self):
        bad_pages = [{"data": [], "links": {}}, {"data": None, "links": {}},
                     self.page(number=True), self.page(number="1028"), self.page(number=-1)]
        for page in bad_pages:
            with self.subTest(page=page), mock.patch.object(self.client, "_get", return_value=page):
                with self.assertRaises(ValueError):
                    self.client.snapshot()
        url = cloud_module.ORIGIN + "/v1/ciProducts/product-id/buildRuns?cursor=next"
        with mock.patch.object(self.client, "_get", side_effect=[self.page(next_url=url), self.page()]):
            with self.assertRaisesRegex(ValueError, "pagination"):
                self.client.snapshot()

    def test_counter_change_and_consumed_candidate_block(self):
        expected = {"product_id": "product-id", "max_number": 1028}
        with mock.patch.object(self.client, "snapshot", return_value=expected):
            self.client.assert_unchanged(expected, 1029)
            with self.assertRaises(ValueError):
                self.client.assert_unchanged(expected, 1028)
        with mock.patch.object(self.client, "snapshot", return_value=dict(expected, max_number=1029)):
            with self.assertRaisesRegex(ValueError, "counter changed"):
                self.client.assert_unchanged(expected, 1029)

    def test_credentials_are_required_and_not_disclosed(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "ASC_CLOUD_PRODUCT_ID"):
                cloud_module.CloudBuildCounter.from_environment()
        with mock.patch.dict(os.environ, {"ASC_CLOUD_PRODUCT_ID": "product-id", "ASC_API_TOKEN": "test-secret"}, clear=True):
            self.assertEqual(cloud_module.CloudBuildCounter.from_environment().product_id, "product-id")

    def test_keychain_token_is_read_without_logging(self):
        env = {"ASC_CLOUD_PRODUCT_ID": "product-id", "ASC_TOKEN_KEYCHAIN_SERVICE": "fixture-service"}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(cloud_module.subprocess, "run", return_value=mock.Mock(stdout="test-secret\n")) as command:
            self.assertEqual(cloud_module.CloudBuildCounter.from_environment().product_id, "product-id")
            self.assertNotIn("test-secret", str(command.call_args))

    def test_pagination_cannot_send_credentials_elsewhere(self):
        for url in ("https://evil.invalid/buildRuns", "http://api.appstoreconnect.apple.com/v1/ciProducts/product-id/buildRuns",
                    cloud_module.ORIGIN + "/v1/ciProducts/another-product/buildRuns"):
            with mock.patch.object(self.client._opener, "open") as opened:
                with self.assertRaisesRegex(ValueError, "unexpected"):
                    self.client._get(url, 1)
                opened.assert_not_called()
        self.assertIsNone(cloud_module.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.invalid"))

    def test_action_requests_are_scoped_to_the_resolved_run(self):
        correct = cloud_module.ORIGIN + '/v1/ciBuildRuns/968/actions'
        for url in (correct.replace('/968/', '/969/'), correct.replace('https:', 'http:'),
                    'https://evil.invalid/v1/ciBuildRuns/968/actions', correct + '#fragment'):
            with mock.patch.object(self.client._opener, 'open') as opened:
                with self.assertRaises(ValueError):
                    self.client._get(url, 1, action_run_id='968')
                opened.assert_not_called()
        with self.assertRaises(ValueError):
            self.client._get(correct, 1, action_run_id='../968')
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{}'
        with mock.patch.object(self.client._opener, 'open', return_value=response) as opened:
            self.client._get(correct, 1, action_run_id='968')
            self.assertEqual(opened.call_args.args[0].get_method(), 'GET')

    def test_auth_rate_limit_and_network_errors_are_sanitized(self):
        url = cloud_module.ORIGIN + "/v1/ciProducts/product-id/buildRuns"
        for status in (401, 403, 429, 500):
            error = cloud_module.urllib.error.HTTPError(url, status, "fixture-token", {}, None)
            with mock.patch.object(self.client._opener, "open", side_effect=error):
                with self.assertRaises(ValueError) as raised:
                    self.client._get(url, 1)
                self.assertNotIn("fixture-token", str(raised.exception))
                self.assertIn(str(status), str(raised.exception))
        with mock.patch.object(self.client._opener, "open", side_effect=TimeoutError("fixture-token")):
            with self.assertRaises(ValueError) as raised:
                self.client._get(url, 1)
            self.assertNotIn("fixture-token", str(raised.exception))

    def test_successful_request_is_read_only_and_bounded(self):
        url = cloud_module.ORIGIN + "/v1/ciProducts/product-id/buildRuns"
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps(self.page()).encode()
        with mock.patch.object(self.client._opener, "open", return_value=response) as opened:
            self.assertEqual(self.client._get(url, 10), self.page())
            request = opened.call_args.args[0]
            self.assertEqual(request.get_method(), "GET")
            self.assertIsNone(request.data)
            self.assertEqual(opened.call_args.kwargs["timeout"], 10)
            response.__enter__.return_value.read.assert_called_once_with(2_000_001)

    def test_malformed_and_oversized_response_block(self):
        url = cloud_module.ORIGIN + "/v1/ciProducts/product-id/buildRuns"
        for payload in (b"not-json", b"[]", b"x" * 2_000_001):
            response = mock.MagicMock()
            response.__enter__.return_value.read.return_value = payload
            with mock.patch.object(self.client._opener, "open", return_value=response):
                with self.assertRaises(ValueError):
                    self.client._get(url, 1)


class TeamKeyAuthenticationTests(unittest.TestCase):
    def setUp(self):
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        self.temp = tempfile.TemporaryDirectory(prefix="nve-auth-test-")
        self.addCleanup(self.temp.cleanup)
        self.key = ec.generate_private_key(ec.SECP256R1())
        self.path = Path(self.temp.name) / "AuthKey_TESTKEY123.p8"
        self.path.write_bytes(self.key.private_bytes(serialization.Encoding.PEM,
                             serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        self.path.chmod(0o600)
        self.key_id = "TESTKEY123"
        self.issuer = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        self.url = cloud_module.ORIGIN + "/v1/ciProducts/product-id/buildRuns?limit=200&fields%5BciBuildRuns%5D=number,executionProgress"

    def signer(self):
        return cloud_module.TeamKeyToken(self.key_id, self.issuer, str(self.path))

    @staticmethod
    def decode(value):
        return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))

    def test_signature_scope_and_renewal(self):
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import ec, utils
        signer = self.signer()
        for now in (1000, 2000):
            with mock.patch.object(cloud_module.time, "time", return_value=now):
                token = signer(self.url)
            header, payload, signature = token.split(".")
            self.assertEqual(json.loads(self.decode(header)), {"alg": "ES256", "kid": self.key_id, "typ": "JWT"})
            claims = json.loads(self.decode(payload))
            self.assertEqual(claims, {"iss": self.issuer, "iat": now, "exp": now + 120,
                             "aud": "appstoreconnect-v1", "scope": ["GET " + self.url.removeprefix(cloud_module.ORIGIN)]})
            raw = self.decode(signature)
            self.assertEqual(len(raw), 64)
            der = utils.encode_dss_signature(int.from_bytes(raw[:32], "big"), int.from_bytes(raw[32:], "big"))
            self.key.public_key().verify(der, (header + "." + payload).encode(), ec.ECDSA(hashes.SHA256()))

        actions_url = cloud_module.ORIGIN + '/v1/ciBuildRuns/968/actions?limit=200'
        claims = json.loads(self.decode(signer(actions_url).split('.')[1]))
        self.assertEqual(claims['scope'], ['GET /v1/ciBuildRuns/968/actions?limit=200'])

    def test_private_key_location_permissions_and_content(self):
        self.path.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "permissions"):
            self.signer()
        self.path.chmod(0o600)
        (self.path.parent / ".git").mkdir()
        with self.assertRaisesRegex(ValueError, "outside Git"):
            self.signer()
        (self.path.parent / ".git").rmdir()
        self.path.write_text("private fixture contents must not appear in errors")
        with self.assertRaisesRegex(ValueError, "P-256") as error:
            self.signer()
        self.assertNotIn("private fixture", str(error.exception))
        self.path.unlink()
        with self.assertRaisesRegex(ValueError, "Could not read"):
            self.signer()

    def test_wrong_curve_and_identifiers_are_rejected(self):
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        self.path.write_bytes(ec.generate_private_key(ec.SECP384R1()).private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        with self.assertRaisesRegex(ValueError, "P-256"):
            self.signer()
        for key_id, issuer in (("", self.issuer), (self.key_id, "not-an-issuer")):
            with self.assertRaises(ValueError):
                cloud_module.TeamKeyToken(key_id, issuer, str(self.path))
        with self.assertRaisesRegex(ValueError, "absolute"):
            cloud_module.TeamKeyToken(self.key_id, self.issuer, "relative.p8")

    def test_authentication_precedence_and_local_configuration(self):
        settings = {"productId": "product-id", "keyId": self.key_id,
                    "issuerId": self.issuer, "privateKeyPath": str(self.path)}
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch.object(cloud_module, "local_setting", side_effect=settings.get):
            client = cloud_module.CloudBuildCounter.from_environment()
            self.assertIsInstance(client._token, cloud_module.TeamKeyToken)
        with mock.patch.dict(os.environ, {"ASC_CLOUD_PRODUCT_ID": "override", "ASC_API_TOKEN": "external-token"}, clear=True), mock.patch.object(cloud_module, "local_setting") as config:
            client = cloud_module.CloudBuildCounter.from_environment()
            self.assertEqual(client.product_id, "override")
            self.assertEqual(client._token, "external-token")
            config.assert_not_called()
        env = {"ASC_CLOUD_PRODUCT_ID": "product-id", "ASC_KEY_ID": self.key_id,
               "ASC_ISSUER_ID": self.issuer, "ASC_PRIVATE_KEY_PATH": str(self.path)}
        with mock.patch.dict(os.environ, env, clear=True), mock.patch.object(cloud_module, "local_setting") as config:
            self.assertIsInstance(cloud_module.CloudBuildCounter.from_environment()._token, cloud_module.TeamKeyToken)
            config.assert_not_called()

    def test_generated_tokens_are_refreshed_only_for_valid_requests(self):
        signer = mock.Mock(return_value="generated-token")
        client = cloud_module.CloudBuildCounter("product-id", signer)
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{}'
        with mock.patch.object(client._opener, "open", return_value=response):
            client._get(self.url, 1)
            client._get(self.url, 1)
            self.assertEqual(signer.call_count, 2)
            with self.assertRaises(ValueError):
                client._get("https://evil.invalid/", 1)
            self.assertEqual(signer.call_count, 2)
        for url in ("https://evil.invalid/", self.url + "#fragment", self.url.replace("https:", "http:")):
            with self.assertRaises(ValueError):
                self.signer()(url)

    def test_local_config_is_never_read_from_global_settings(self):
        with mock.patch.object(cloud_module.subprocess, "run", return_value=mock.Mock(returncode=0, stdout="fixture\n")) as run:
            self.assertEqual(cloud_module.local_setting("keyId"), "fixture")
            self.assertIn("--local", run.call_args.args[0])
            self.assertIn("nve.asc.keyId", run.call_args.args[0])
        with mock.patch.object(cloud_module.subprocess, "run", return_value=mock.Mock(returncode=1)):
            self.assertEqual(cloud_module.local_setting("keyId"), "")


if __name__ == "__main__":
    unittest.main()
