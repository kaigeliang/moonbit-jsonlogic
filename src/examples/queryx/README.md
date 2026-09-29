# Native QueryX integration verifier

From the repository root, run:

```sh
PGHOST=localhost PGPORT=5432 PGUSER=postgres PGDATABASE=postgres \
  python3 tools/check_queryx.py
```

Use your own PostgreSQL connection environment variables. The command reads
`tests/queryx_fixture.json`, invokes this native executable, and compares the
pinned JavaScript reference, the MoonBit JSONLogic core, QueryX `Expr.eval`, and
the actual foxql SQL result from PostgreSQL. SQL uses `PREPARE` with typed
bindings, generated table/column names, and temporary tables inside rolled-back
transactions. Text columns explicitly use the `C` collation.

The script saves fixture snapshots, raw evaluator output, SQL and bindings,
rejection JSON Pointers, and a deliberately changed-parameter negative control
under `output/queryx/`. The executable accepts one JSON fixture argument; use the
Python command to run the complete comparison.

This example is native only because QueryX 0.2.1 and foxql 0.1.3 are native only.
It does not serialize QueryX expressions to JSON before evaluation or SQL
generation. The supported filter/record contract is documented in
`docs/queryx-integration.md`.
