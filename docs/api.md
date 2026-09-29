# API and integration

Import `kaigeliang/jsonlogic` as `@logic`. The runtime uses only `moonbitlang/core`.

## Evaluation

```moonbit
let value = @logic.apply(rule, data)
let value_from_text = @logic.apply_json(rule_text, data_text)
let result = @logic.evaluate(rule, data, max_steps=100000, max_depth=128)
```

All three functions raise `LogicError`. `evaluate` returns:

| Field | Type | Meaning |
| --- | --- | --- |
| `value` | `Json` | Rule result; may be any JSON type |
| `logs` | `Array[Json]` | Values from evaluated `log` operations in evaluation order |
| `steps_used` | `Int` | Input traversal and evaluation visits consumed |

`truthy(value)` implements JSONLogic truthiness. In particular, `[]` is false and `"0"` is true.

## Errors

| Variant | Meaning |
| --- | --- |
| `InvalidRule(path, message)` | Unknown operator, unsupported argument structure or an unpaired-surrogate string result |
| `LimitExceeded(path)` | Input/evaluation nesting or step budget exhausted |
| `NonFiniteNumber(path)` | Arithmetic produced NaN or infinity |
| `InvalidInput(message)` | Invalid JSON text, oversized text, non-finite input number, invalid Unicode string or invalid budget settings |

`path` is a JSON Pointer into the rule; `""` denotes the root. Input-validation errors use the root. For collection operations, the pointer identifies the rule being evaluated, not the current data item. `error.to_string()` produces a readable diagnostic.

## Input and execution bounds

- `max_steps` defaults to 100,000 and must be positive. It includes visits to both input documents, evaluated rule nodes and selected collection operations. A repeated collection rule consumes steps on every evaluation.
- `max_depth` defaults to 128 and must be between 1 and 256. Input nesting is checked before execution, including unselected branches.
- `apply_json` limits each text input to 2,097,152 UTF-16 code units before parsing.
- Limits do not bound every byte allocation, string operation, JSON parsing cost or wall-clock duration. Services accepting untrusted rules should also bound request sizes and use their own time/memory isolation.
- Evaluation does not mutate the inputs. Returned arrays/objects can share references with input data; callers needing an isolated snapshot should copy it.

## Browser and server use

Compile the same MoonBit module to JS for a browser integration or to native/Wasm for a service. Transport rules and input as JSON and evaluate them at the application boundary. This repository provides the evaluator; application HTTP endpoints and a prebuilt npm/browser wrapper are not included.

`log` never prints or performs I/O. Use `evaluate(...).logs` when you want to expose traces in your application. `apply` returns only the result.

## Workspace integration

The repository's `moon.work` includes the library and its conformance executable. Your application's own workspace only needs your module and this repository's root module. The conformance executable, Node reference implementation and Python runner are development tools.

See [the generated public interface](../src/pkg.generated.mbti) for exact signatures and [examples](../src/examples/) for complete programs.
