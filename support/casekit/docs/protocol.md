# CaseKit v1 protocol

A transcript is one JSON object:

```json
{"casekit":1,"suite":"example","cases":[{"id":"sort","value":[1,2,3]}]}
```

The root must contain exactly `casekit`, `suite` and `cases`. The version is the
number 1. `suite` is a nonblank string. `cases` is a nonempty array of objects,
each containing exactly `id` (a nonblank string) and `value` (a JSON value).
Case IDs must be unique. Suite names must match before comparison.

Encoding sorts case IDs and object keys lexicographically. Decoding accepts other
orders. Array order is meaningful. JSON object key parsing follows MoonBit core's
JSON parser; producers should never emit duplicate object keys. Case IDs are
separate array records, so duplicate IDs are always rejected.

Values are deep copied at observation time. Non-finite JSON numbers and values
nested more than 64 levels are rejected. `decode` rejects input longer than
2,097,152 UTF-16 code units. This is an in-memory protocol for small deterministic
test observations, not a streaming format for large datasets.

## Reports

`Report::encode()` returns a JSON object with:

| Field | Meaning |
| --- | --- |
| `suite` | Common suite name |
| `total_cases` | Number of IDs in the union of both runs |
| `matched_cases` | Number of IDs present in both with matching values |
| `abs_tol`, `rel_tol` | Applied numeric tolerances |
| `differences` | Ordered array of differences |

Each difference includes `case_id`, `path`, and `kind`. `expected` or `actual` is
omitted for a missing value; an explicit JSON null remains present as `null`.
Kinds use MoonBit's derived enum encoding. The generated API lists all variants.
Paths are JSON Pointers within the case value: `~` in a key becomes `~0`, `/` becomes
`~1`, and the case root is `""`.

The human report escapes case IDs and paths and distinguishes `<missing>` from
`null`. Its display limit does not change the stored differences or exit status.

Do not interpret an invalid or incomplete transcript as a matching run. The CLI
returns 2 for validation or execution errors, distinct from 1 for a valid mismatch.
