# v0.7.5 Performance Smoke Notes

Date: 2026-06-04

## Commands

```bash
scripts/benchmark_large_file.sh 100000
scripts/benchmark_large_file.sh 250000
scripts/benchmark_large_file.sh 500000
```

## Results

| Scenario | Generation time | Swift sample | JSON sample | Markdown sample |
| --- | ---: | ---: | ---: | ---: |
| 100k | 263 ms | 100,000 lines / 7,377,790 bytes | 100,002 lines / 5,877,806 bytes | 500,002 lines / 9,266,713 bytes |
| 250k | 570 ms | 250,000 lines / 18,777,790 bytes | 250,002 lines / 15,027,806 bytes | 1,250,002 lines / 23,666,713 bytes |
| 500k | 669 ms | 500,000 lines / 37,777,790 bytes | 500,002 lines / 30,277,806 bytes | 2,500,002 lines / 47,666,713 bytes |

## Manual Smoke Checklist

- Open the Swift sample, toggle invisible characters, and scroll from top to bottom.
- Open the JSON sample and confirm large-file syntax highlighting stays responsive.
- Open the Markdown sample, open preview, switch templates, then export PDF.
- Run Find in Files for `benchmark line` and confirm results remain interactive.
- Compare the Swift sample against a modified copy and confirm large diffs are guarded.
