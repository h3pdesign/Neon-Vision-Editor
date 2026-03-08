# Claude Export Fixture 1

## Overview

This fixture mixes prose, lists, code fences, inline code, table rows, and emphasis markers like _snake_case_ and `token_name`.

- Step 1: Parse data from `input.json`
- Step 2: Validate using **strict mode**
- Step 3: Emit report for `2026-03-08`

### Nested Structure

> Note: This section intentionally includes repeated symbols and underscore-heavy text.

1. Item one with `inline_code()` and _italic text_.
2. Item two with `foo_bar_baz` and **bold text**.
3. Item three with [link text](https://example.com/docs?q=alpha_beta).

```swift
struct ReportRow {
    let id: String
    let score: Double
}

func render(rows: [ReportRow]) -> String {
    rows.map { "\($0.id): \($0.score)" }.joined(separator: "\n")
}
```

```json
{
  "section": "analysis",
  "items": ["alpha_beta", "gamma_delta"],
  "ok": true
}
```

| key | value |
| --- | ----- |
| user_id | abcd_1234 |
| run_id | run_2026_03_08 |

End of fixture.
