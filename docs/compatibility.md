# Compatibility contract

This contract applies to the JSONLogic evaluation core. The [native QueryX/foxql adapter](queryx-integration.md) has a narrower filter-import contract and a separate PostgreSQL verification suite. The 315-case evaluation corpus does not itself verify database queries.

The reference is **json-logic-js 2.0.5**, pinned to the commit in [the provenance record](../third_party/json-logic-js/README.md). This implementation supports the standard built-in rule operators over JSON data.

## Covered behaviors

- JSONLogic truthiness, including false empty arrays and true `"0"` strings.
- Lazy `if`, `and`, `or`, `all`, `some` and `none` evaluation.
- Local data scope in `map`, `filter`, `all`, `some`, `none`; `current`/`accumulator` scope in `reduce`. The initial reduce value is evaluated in the outer scope.
- Dotted `var` lookup, array/string indexes, UTF-16 `length`, fallback for absent paths, preservation of explicit nulls.
- JavaScript-style loose/strict equality for JSON values. Arrays and objects use reference identity for strict equality; separately constructed arrays with identical contents are not equal.
- `+`/`*` use parseFloat-style conversion; other arithmetic uses Number-style conversion. This intentionally means `{"+":["2kg",1]}` returns 3, while subtraction with `"2kg"` fails with a non-finite result.
- Lexical string comparisons; UTF-16 `substr` indexing, including the reference library's negative length behavior.
- `merge` flattens one level; `missing` treats null/empty strings as missing, while false/zero remain present.

## Deliberate boundaries

| Area | Behavior here |
| --- | --- |
| NaN / infinity | Input numbers and final numeric results are rejected. JSON has no representation for these values. They are not silently converted to null. |
| JavaScript undefined | Operations with missing required operands, and empty `and`/`or`, raise an error. Other malformed arities are not promised to match JavaScript. |
| Object properties | Only JSON's own fields are available. No inherited properties such as `constructor` or JavaScript prototype methods. Own keys named `__proto__` are ordinary JSON data. |
| Unicode | Strings must contain valid Unicode scalar sequences. UTF-16 indexing is preserved, but a substring/index lookup that splits a surrogate pair raises `InvalidRule`; unpaired surrogate inputs are rejected. |
| Custom operators | `add_operation`, `rm_operation`, arbitrary callbacks and dotted custom method calls are not implemented. |
| Utility API | The JavaScript helpers `uses_data` and `rule_like` are not part of this API. |
| Logging | `log` returns its operand and appends it to `Evaluation.logs`; it does not write to a console. |
| Numbers | IEEE-754 doubles, with the same precision limits as JavaScript numbers. Exact decimal currency/arbitrary-precision integers require an application-level representation. |
| Missing keys | Use string/number path keys. Nested rule objects supplied as computed keys to `missing` are outside the supported contract. |
| Limits | Input traversal/evaluation budgets are enforced. They can reject a rule that an unrestricted JS evaluator would execute. |

These boundaries should be considered when importing existing rule catalogs. Passing the current suite is evidence for those inputs, not a proof of full JavaScript equivalence.

## Reproduce the comparison

```sh
python3 tools/check_compat.py
```

1. `tools/reference.cjs` runs the unchanged vendored JS implementation. For official fixtures it first checks the reference result against the fixture's expected value.
2. The generated `compat/src/cases.mbt` supplies identical inputs without filesystem or JavaScript FFI dependencies to each backend.
3. `tools/check_compat.py` compares the reference results to each MoonBit result by case ID. JSON types, nested values and array order must match; object key order is ignored. JSON numbers are parsed as exact decimals and compared without tolerance.
4. The script deliberately changes a reference result and requires the comparison to report a difference. Invalid result files and mismatches both fail the CI command.

Current corpus: **278 official + 37 edge cases = 315**, on native, JS, Wasm and Wasm GC. Edge coverage includes identity, lazy failures, UTF-16, coercion, Infinity string comparisons, ECMAScript whitespace and collection scoping. Separate unit tests cover errors, budget exhaustion, log capture and own-property semantics.

To add a regression, append a named rule/data pair to `tests/edge_cases.json`, then run:

```sh
python3 tools/generate_cases.py
moon fmt
python3 tools/check_compat.py
```

Errors and deliberate divergences belong in `src/logic_test.mbt`, not in the equal-result corpus. Do not rewrite the vendored upstream files to make a test pass.
