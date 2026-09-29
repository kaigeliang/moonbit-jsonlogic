# API and integration

The source checkout contains the native [QueryX/foxql adapter](queryx-integration.md) and the portable evaluation core. The published Mooncakes 0.1.0 release contains only the evaluation core.

## QueryX import (native, source workspace)

Import `kaigeliang/jsonlogic/queryx` as `@adapter`. The package returns the actual upstream QueryX `Expr`:

```moonbit
let fields = [@adapter.Field::{ name: "age", kind: @adapter.FieldType::Number }]
@adapter.validate_record({ "age": 22 }, fields)
let expr = @adapter.import_filter({ ">=": [{ "var": "age" }, 18] }, fields)
```

`FieldType::Number` accepts **Int32 integers**, `String` accepts valid non-NUL Unicode text, and `Bool` accepts JSON booleans. Record validation requires every declared field to be present, non-null and of the declared type. Extra keys are allowed but still receive full input validation.

`import_filter(rule, fields, max_nodes=10000, max_depth=64)` and `validate_record(data, fields, max_nodes=10000, max_depth=64)` raise `ImportError`. The variants are `InvalidRule(path, reason)`, `InvalidRecord(path, reason)`, `InvalidFields(path, reason)`, and `LimitExceeded(path)`; `to_string()` renders them. Both functions check the entire JSON input, including subtrees that a later evaluator might skip. Limits are positive; `max_depth` must be between 1 and 128. Declare 1–1000 unique, nonempty top-level field names without dots.

Use the returned Expr directly with QueryX's `eval` / `to_foxql_expr`, a trusted `FieldResolver`, and foxql. The SQL schema must enforce matching non-null column types and deterministic PostgreSQL `C` text equality. Do not serialize and reparse the Expr through QueryX's JSON DSL. See [the runnable integration program](../src/examples/queryx/main.mbt) and [the generated adapter interface](../src/queryx/pkg.generated.mbti).

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

The repository's `moon.work` includes the library and its conformance executable. Your application's own workspace needs your module and this repository's root module. The query adapter resolves QueryX/foxql dependencies from the root manifest; applications importing QueryX by name should also declare that dependency. The conformance executable, Node reference implementation and Python runner are development tools. `tools/check_consumer.py` compiles separate applications against the core on native/JS and the query adapter on native.

See [the generated public interface](../src/pkg.generated.mbti) for exact signatures and [examples](../src/examples/) for complete programs.
