#!/usr/bin/env python3
"""README "Last updated" must not move backwards for the same release."""
import importlib.util
import pathlib
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolve postponed annotations through sys.modules.
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        sys.modules.pop(name, None)
        raise
    return module


README = "> Last updated (README): **2026-10-23** for latest release **v2.1.0**\n"


class ReadmeLastUpdatedTests(unittest.TestCase):
    def test_writers_keep_the_later_date_for_the_same_release(self):
        for name in ("update_download_metrics", "sync_readme_appstore_versions"):
            module = load(name)
            with self.subTest(script=name):
                # A UTC run on the evening before the release's local date.
                self.assertEqual(module.readme_last_updated_date(README, "v2.1.0", "2026-10-22"), "2026-10-23")
                self.assertEqual(module.readme_last_updated_date(README, "v2.1.0", "2026-10-24"), "2026-10-24")
                # A new release always takes the current date.
                self.assertEqual(module.readme_last_updated_date(README, "v2.2.0", "2026-10-22"), "2026-10-22")
                legacy = README.replace("latest release", "release line")
                self.assertEqual(module.readme_last_updated_date(legacy, "v2.1.0", "2026-10-22"), "2026-10-23")

    def test_store_sync_updates_the_readme_without_claiming_unverified_store_status(self):
        module = load("sync_readme_appstore_versions")
        readme = (SCRIPTS.parent / "README.md").read_text(encoding="utf-8")
        for store_tag in ("v1.9.2", "v9.9.9"):
            with self.subTest(store=store_tag):
                updated = module.sync_readme_versions(readme, "v9.9.9", store_tag, "2026-10-24")
                self.assertIn("> Direct GitHub release: **v9.9.9**", updated)
                self.assertIn(f"| **{store_tag}** | Current public App Store listing |", updated)
                self.assertNotIn("In Apple review", updated)
                self.assertNotIn("currently in Apple review", updated)
                for row in ("| **Store status** | macOS |", "| **Beta** | iOS / iPadOS / macOS |"):
                    line = next(line for line in updated.splitlines() if line.startswith(row))
                    self.assertIn("**Not verified**", line)
                # A second sync is a no-op.
                self.assertEqual(module.sync_readme_versions(updated, "v9.9.9", store_tag, "2026-10-24"), updated)


if __name__ == "__main__":
    unittest.main()
