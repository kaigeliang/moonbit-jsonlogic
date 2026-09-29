# React Query Builder fixture producer

This isolated development dependency calls the actual export function from
`@react-querybuilder/core` **8.24.3**. It does not implement a substitute exporter.
The package is the shared core used by React Query Builder and its official
framework ports; source and documentation links are saved in the fixture.

```sh
cd tools/queryx-fixtures
npm ci --ignore-scripts --no-audit --no-fund
npm run generate
npm run check
```

The output is `tests/queryx_fixture.json`. Every positive case saves the original
query tree, unmodified JSONLogic export, declared column types and complete input
records. The fixtures cover age/status user filters, status/amount order filters,
boolean equality, nested nonempty groups, group negation, Int32 limits, Unicode
and apostrophe/quote characters. The SQL-looking status value checks that a string
parameter remains data.

The `rqb/numeric-string-export` rejection saves a real query-tree export: the
default producer preserves `'18'` as a string, which cannot be compared with an
Int32 column in the adapter's same-type subset. A positive export compares a
string column with `'001'`, preserving its type and leading zeros.

The other rejection cases are handwritten **negative contract probes**, identified
as such in producer metadata. They do not claim that the upstream query builder
necessarily exports each unsupported construct. They cover nulls, type coercion,
dynamic variables, collection scopes, unknown fields/operators, variable defaults,
nested paths, fractional numbers and Int32 overflow. Invalid record fixtures also
exercise the nonnullable typed input contract.

Every rejection specifies an independent `expected_error` kind and JSON Pointer
to the contract violation. These expectations are written from the source AST
and record schema, not copied from the adapter's reported errors. The integration
gate must reject a refusal that reports the wrong category or source location.

`--check` regenerates in memory and compares the complete fixture byte for byte.
There are no timestamps, random IDs or network requests in generation. Install
uses the committed lockfile; npm registry tarball integrity is recorded there.
This verifies producer reproducibility. The independent database integration
check is responsible for comparing filtered record IDs with MoonBit and the
pinned reference interpreter.
