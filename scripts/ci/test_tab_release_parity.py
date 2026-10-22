import json
import pathlib
import tempfile
import unittest

from check_tab_release_parity import METRICS, MIN_SAMPLES, compare, read_runs, summarize


class TabReleaseParityTests(unittest.TestCase):
    def test_regression_in_either_median_or_tail_fails(self):
        key = ("preview", "typing_Small.swift_ms")
        self.assertFalse(compare({key: [10] * 20}, {key: [9] * 20})[0]["regressed"])
        self.assertTrue(compare({key: [10] * 20}, {key: [11] * 20})[0]["regressed"])
        self.assertTrue(compare({key: [10] * 20}, {key: [9] * 18 + [30] * 2})[0]["regressed"])

    def test_zero_and_percentile_boundaries(self):
        self.assertEqual(summarize([0]), (0, 0))
        self.assertEqual(summarize(list(range(1, 21))), (10.5, 19))
        key = ("edit", "close_dispatch_ms")
        self.assertTrue(compare({key: [0]}, {key: [0.01]})[0]["regressed"])

    def test_mismatched_workloads_fail(self):
        with self.assertRaises(ValueError):
            compare({("preview", "a"): [1]}, {("edit", "a"): [1]})

    def test_evidence_must_be_complete_repeated_and_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = [pathlib.Path(directory) / f"run{i}.log" for i in range(3)]
            records = ["TAB_RELEASE_PARITY " + json.dumps({"evidence_version": 2, "variant": "native", "preview": "preview",
                       "metric": metric, "samples": [10] * MIN_SAMPLES[metric]}) for metric in sorted(METRICS)]
            text = "\n".join(records + ["TAB_RELEASE_PARITY_COMPLETE"])
            for path in paths:
                path.write_text(text)
            self.assertEqual(len(read_runs(paths, "native")), len(METRICS))
            with self.assertRaises(ValueError):
                read_runs(paths[:1], "native")
            with self.assertRaises(ValueError):
                read_runs(paths, "release")
            for invalid in ("", text.replace("TAB_RELEASE_PARITY_COMPLETE", ""),
                            text.replace('"evidence_version": 2, ', ''),
                            text.replace('"evidence_version": 2', '"evidence_version": 1'),
                            "\n".join(records[1:] + ["TAB_RELEASE_PARITY_COMPLETE"]),
                            text.replace('[10]', '[NaN]'), text.replace('[10]', '[]'),
                            text.replace('[10, 10, 10]', '[10]'),
                            text + "\nTAB_RELEASE_PARITY_COMPLETE",
                            text + "\nTAB_RELEASE_PARITY_DIAGNOSTIC_PAUSE"):
                paths[0].write_text(invalid)
                with self.assertRaises(ValueError):
                    read_runs(paths, "native")


if __name__ == "__main__":
    unittest.main()
