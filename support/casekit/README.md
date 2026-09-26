# MoonBit CaseKit

**An original MoonBit behavior testing library, designed and implemented by Kaige Liang.**

CaseKit is an independently reusable library delivered alongside [MoonBit JSONLogic](../../README.md). Its observation API, versioned transcript protocol, structural comparator, reports, native CLI and multi-backend runner are developed in this project. The JSONLogic conformance suite uses these APIs to compare the original JavaScript implementation with four MoonBit backends.

Record the behavior of a MoonBit program and compare it across **native, JavaScript,
Wasm and Wasm-GC**. CaseKit reports the case ID, nested path, expected value and actual
value when runs disagree. Use it when porting a library, changing a compiler version,
or checking serialization and numeric behavior across backends.

The collection, validation and comparison library is written in MoonBit. A native
MoonBit CLI compares saved transcripts; a small Python script runs your observation
package on multiple backends and connects the results to CI.

## Use the copy in this repository

From the `moonbit-jsonlogic` repository root:

```sh
# CaseKit's own four-backend Unicode/JSON example
python3 support/casekit/tools/check_targets.py

# The JSONLogic integration, checked against the pinned JavaScript original
python3 tools/check_compat.py

# Compare two saved CaseKit transcripts
moon run support/casekit/src/cli --target native -- expected.json actual.json
```

To use this copy in another application, add `support/casekit` as a member of your
application's `moon.work` and import `kaigeliang/casekit@0.1.0` in its `moon.mod`.
Use a path relative to that workspace file. The API example below applies to both
this copy and the independent CaseKit checkout. Commands after this section assume
the independent checkout shown next.

## Try it

Prerequisites: [MoonBit](https://www.moonbitlang.com/download/), a C compiler for the
native backend, Node.js for JS, and Python 3.10+. MoonBit supplies `moonrun` for Wasm.
The initial release was tested with moonc v0.10.14 and moon 0.1.20260920 on macOS;
the workflow also checks Linux with the current stable toolchain.

```sh
git clone https://github.com/kaigeliang/moonbit-casekit.git
cd moonbit-casekit
moon update
python3 tools/check_targets.py
```

The command runs the Unicode/JSON example on all four backends. The first target
(native by default) is the reference. Each execution gets its own directory under
`output/casekit/`, containing transcripts and comparison reports.

```sh
# Other runnable use cases
python3 tools/check_targets.py --package src/examples/numeric
python3 tools/check_targets.py --package src/examples/collections

# Print an intentional mismatch, including nested array and type differences
moon run --target native src/examples/canary

# Select backends, optimization mode and an explicit floating-point tolerance
python3 tools/check_targets.py --targets native js --release --abs-tol 0.000001
```

The canary intentionally constructs different values. It demonstrates diagnostics;
it is not evidence of a compiler defect.

## Record observations in your library

Version 0.1.0 is available from this source repository. It has **not been published
to mooncakes.io**. To use it in another module, place both modules in a local MoonBit
workspace. For sibling directories, create `moon.work` in their parent:

```moonbit
members = ["./my-library", "./moonbit-casekit"]
```

Add `"kaigeliang/casekit@0.1.0"` to your module's `moon.mod` import declaration.
In an observation executable's `moon.pkg`, use:

```moonbit
import {
  "kaigeliang/casekit" @casekit,
}
pkgtype(kind: "executable")
```

Then record JSON values with stable case IDs:

```moonbit
fn main raise {
  let suite = @casekit.Suite::new("my-library")
  suite.observe("sorted", [1, 2, 3].to_json())
  suite.observe("message", "你好🌙".to_json())
  suite.observe_number("decimal-sum", 0.1 + 0.2)
  println(suite.encode())
}
```

Call the runner from this checkout, pointing to your module and executable:

```sh
python3 tools/check_targets.py --project ../my-library --package src/observations
```

The executable must print exactly one transcript to stdout. Send diagnostic logs
elsewhere. `observe` takes a deep snapshot, so later mutation of a JSON array or
object cannot change an already recorded case. Empty suites and duplicate IDs are
errors. See the [examples](src/examples/README.md) and [public API](src/pkg.generated.mbti).

## Compare saved runs

```sh
moon build --target native
_build/native/debug/build/cli/cli.exe expected.json actual.json
_build/native/debug/build/cli/cli.exe --json expected.json actual.json
_build/native/debug/build/cli/cli.exe --abs-tol 0.000001 expected.json actual.json
```

Both CLI and runner use these exit codes:

| Code | Meaning |
| --- | --- |
| 0 | All recorded cases match |
| 1 | Valid runs differ |
| 2 | Invalid input, invalid settings, build/runtime failure or timeout |

The library also compares decoded transcripts directly:

```moonbit
let report = @casekit.compare(@casekit.decode(expected), @casekit.decode(actual))
println(report.render())
println(report.encode()) // JSON report for another tool
```

## Comparison rules

- Cases are matched by ID. Case order and object key order do not matter; array
  order does. Missing cases, missing fields, `null` and different JSON types remain distinct.
- Nested differences use JSON Pointer paths, such as `/items/0/name`. An empty path
  means the case root. Human output shows the first 20 differences by default;
  the JSON report retains all differences.
- Numbers compare exactly by default. Explicit tolerances allow
  `abs(a-b) <= abs_tol` **or** a relative error bounded by `rel_tol`.
  Tolerances apply to every numeric observation in that comparison.
- Use `observe_number` for floating-point values: it rejects NaN and infinity
  before JSON conversion. Calling `.to_json()` yourself may already convert a
  non-finite value to `null`, which CaseKit cannot recover.
- Encode exact 64-bit integers as strings. The comparator preserves differences
  between retained high-precision JSON number spellings, but is not an arbitrary
  precision arithmetic library. With tolerance enabled, numbers use Double precision.
  Positive and negative zero compare equal; record a string or bit pattern when
  their distinction matters.
- Strings compare without Unicode normalization. Observation values have a nesting
  limit of 64; decoded transcripts have a limit of 2,097,152 UTF-16 code units.

CaseKit checks the observations you choose. Matching runs do not prove program
correctness, and the reference backend is not automatically correct. Keep inputs
deterministic, seed random generators and avoid recording timestamps or unordered
iteration results unless those are the behavior under test.

`moon test --target ...` runs assertions on each backend; CaseKit adds a reusable
record-and-compare layer when you want to detect disagreement without writing an
expected value for every case. It does not generate test inputs or shrink failures.

See [the v1 protocol](docs/protocol.md) for transcript and report details.

## Run checks

```sh
moon fmt --check
moon test --target native
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon build --target native
python3 -m unittest discover -s tests -v
```

The core imports only MoonBit core packages. The native CLI uses
`moonbitlang/async`; Python orchestration uses only the standard library.

## License

[MIT](LICENSE), copyright 2026 Kaige Liang.
