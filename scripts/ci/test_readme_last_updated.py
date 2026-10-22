#!/usr/bin/env python3
"""README "Last updated" must not move backwards for the same release."""
import importlib.util
import pathlib
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
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


if __name__ == "__main__":
    unittest.main()
