# Runnable examples

Each observation program prints a CaseKit transcript. Run the same program on each
backend and compare its output with the native CLI.

| Package | Use case | Recorded behavior |
| --- | --- | --- |
| `text` | Text processing and JSON codecs | Unicode code points, UTF-16 length, escaped JSON |
| `numeric` | Numeric libraries | Floating-point sums, exact large-integer strings, integer aggregation |
| `collections` | Algorithms and data structures | Sort order, duplicates, filtering, map contents |
| `canary` | Learn to read a report | Deliberately changed order and a boolean changed to a string |

```sh
moon run --target native src/examples/text
moon run --target js src/examples/text
moon run --target native src/examples/canary
```

The canary is an intentional example, not evidence of a MoonBit compiler bug.
The other three examples compare implementations of the same program; agreement
means these observations match, not that every possible input is correct.
