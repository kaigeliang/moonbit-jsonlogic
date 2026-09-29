#!/usr/bin/env python3
"""Compare a real RQB export through JS, MoonBit, QueryX, and PostgreSQL.

The adapter and QueryX/foxql bridge run in the native MoonBit executable.
PostgreSQL receives the exact emitted SQL with PREPARE/typed EXECUTE bindings.
All tables are temporary and every psql session ends with ROLLBACK. Set the
usual PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE variables for your server.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TYPES = {"int32": "INTEGER", "string": "TEXT", "bool": "BOOLEAN"}
REFERENCE = r"""
const fs = require('node:fs');
const logic = require(process.argv[2]);
const fixture = JSON.parse(fs.readFileSync(0, 'utf8'));
const queries = fixture.queries.map(query => {
  const records = query.data.map(row => {
    const value = logic.apply(query.rule, row);
    if (typeof value !== 'boolean') throw Error(query.id + ': nonboolean result');
    return {id:row.id, value};
  });
  return {id:query.id, records,
    matched_ids:records.filter(row => row.value).map(row => row.id).sort((a,b)=>a-b)};
});
process.stdout.write(JSON.stringify({reference:'json-logic-js@2.0.5', queries}) + '\n');
"""


def write_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def execute(command: list[str], stem: Path, *, stdin: str | None = None,
            environment: dict[str, str] | None = None, timeout: int = 180) -> str:
    # Record commands separately; credentials stay in PG environment variables.
    # The MoonBit command carries fixture JSON, not credentials.
    write_json(stem.with_suffix(".command.json"), command)
    result = subprocess.run(command, cwd=ROOT, input=stdin, capture_output=True,
                            text=True, env=environment, timeout=timeout)
    stem.with_suffix(".stdout.txt").write_text(result.stdout)
    stem.with_suffix(".stderr.txt").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"{stem.name} exited {result.returncode}; "
                           f"see {stem.with_suffix('.stderr.txt')}")
    return result.stdout


def scalar_literal(value: object, kind: str) -> str:
    """Encode fixed fixture scalars for typed PREPARE/EXECUTE, never SQL text."""
    if kind == "int32":
        if type(value) is not int or not -(2**31) <= value < 2**31:
            raise ValueError("fixture/binding is not an Int32")
        return str(value)
    if kind == "bool":
        if type(value) is not bool:
            raise ValueError("fixture/binding is not a boolean")
        return "TRUE" if value else "FALSE"
    if kind == "string":
        if not isinstance(value, str) or "\x00" in value:
            raise ValueError("fixture/binding is not PostgreSQL text")
        # SET standard_conforming_strings=on makes backslashes literal.
        value.encode("utf-8", errors="strict")
        return "'" + value.replace("'", "''") + "'"
    raise ValueError(f"unrecognized parameter type {kind!r}")


def sql_program(query: dict, output: dict, parameters: list[dict]) -> str:
    """Use only generated identifiers and actual foxql parameterized SQL."""
    fields = output["fields"]
    if len(fields) != len(query["schema"]):
        raise ValueError("emitted field mapping does not cover fixture schema")
    seen = set()
    declarations = ["id INTEGER PRIMARY KEY"]
    columns = ["id"]
    for index, field in enumerate(fields):
        name, column, kind = field["field"], field["column"], field["type"]
        if column != f"f{index}" or name in seen or query["schema"].get(name) != kind:
            raise ValueError("invalid emitted safe field mapping")
        seen.add(name)
        columns.append(column)
        collation = ' COLLATE "C"' if kind == "string" else ""
        declarations.append(f"{column} {TYPES[kind]}{collation} NOT NULL")
    if seen != set(query["schema"]):
        raise ValueError("emitted field mapping omits schema fields")
    tuples = []
    ids = set()
    for row in query["data"]:
        identity = row["id"]
        id_literal = scalar_literal(identity, "int32")
        if identity in ids:
            raise ValueError("record IDs must be unique within each query")
        ids.add(identity)
        values = [id_literal] + [scalar_literal(row[f["field"]], f["type"])
                                  for f in fields]
        tuples.append("(" + ", ".join(values) + ")")
    if not tuples:
        raise ValueError("each verification query needs a nonempty dataset")
    sql = output["sql"]
    # The trusted builder should emit only our fixed table/column identifiers,
    # operators and placeholders. Never accept arbitrary SQL from a fixture.
    tokens = re.findall(r"jl_rows\.(?:id|f\d+)|\$\d+|[A-Za-z_]+|[<>=!]+|[(),*]", sql)
    allowed = {"SELECT", "FROM", "jl_rows", "WHERE", "AND", "OR", "NOT",
               "ORDER", "BY", "ASC", "=", "!=", "<>", ">", "<", ">=", "<=",
               "(", ")", ","}
    remainder = re.sub(r"jl_rows\.(?:id|f\d+)|\$\d+|[A-Za-z_]+|[<>=!]+|[(),*]", "", sql)
    if remainder.strip() or any(t not in allowed and not re.fullmatch(
            r"jl_rows\.(?:id|f\d+)|\$\d+", t) for t in tokens):
        raise ValueError("foxql SQL contains a token outside the filter contract")
    placeholders = {int(number) for number in re.findall(r"\$(\d+)", sql)}
    if placeholders != set(range(1, len(parameters) + 1)):
        raise ValueError("SQL placeholders do not match emitted bindings")
    parameter_types = ", ".join(TYPES[p["type"]] for p in parameters)
    binding_values = ", ".join(scalar_literal(p["value"], p["type"])
                               for p in parameters)
    prepared = f"PREPARE jl_check ({parameter_types}) AS {sql};"
    execute_sql = f"EXECUTE jl_check ({binding_values});"
    return "\n".join([
        "BEGIN;",
        "SET LOCAL standard_conforming_strings = on;",
        "CREATE TEMP TABLE jl_rows (" + ", ".join(declarations) + ") ON COMMIT DROP;",
        "INSERT INTO jl_rows (" + ", ".join(columns) + ") VALUES " + ",\n".join(tuples) + ";",
        prepared,
        execute_sql,
        "DEALLOCATE jl_check;",
        "ROLLBACK;",
        "",
    ])


def postgres_ids(query: dict, output: dict, parameters: list[dict], stem: Path,
                 psql: str, environment: dict[str, str]) -> list[int]:
    program = sql_program(query, output, parameters)
    sql_path = stem.with_suffix(".sql")
    sql_path.write_text(program)
    raw = execute([psql, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
                   "-f", str(sql_path)], stem, environment=environment)
    lines = raw.splitlines()
    if any(not re.fullmatch(r"-?\d+", line) for line in lines):
        raise ValueError(f"unexpected PostgreSQL query output in {stem}")
    return sorted(int(line) for line in lines)


def mutate_parameter(parameter: dict) -> dict:
    changed = deepcopy(parameter)
    if changed["type"] == "int32":
        changed["value"] = -(2**31) if changed["value"] != -(2**31) else 2**31 - 1
    elif changed["type"] == "bool":
        changed["value"] = not changed["value"]
    elif changed["type"] == "string":
        changed["value"] += "__negative_control__"
    else:
        raise ValueError("unrecognized negative control type")
    return changed


def run(args: argparse.Namespace, directory: Path) -> dict:
    fixture_text = args.fixture.read_text()
    fixture = json.loads(fixture_text)
    if not fixture["queries"]:
        raise ValueError("no positive producer cases")
    (directory / "fixture.json").write_text(fixture_text)
    environment = os.environ.copy()
    environment.setdefault("PGDATABASE", "postgres")
    # This directory is the standard MoonBit installation; PATH still wins.
    environment["PATH"] = str(Path.home() / ".moon/bin") + os.pathsep + environment["PATH"]
    moon = shutil.which("moon", path=environment["PATH"])
    node = shutil.which("node", path=environment["PATH"])
    psql = shutil.which("psql", path=environment["PATH"])
    if not all((moon, node, psql)):
        raise RuntimeError("moon, node and psql must be installed and on PATH")
    database_raw = execute([psql, "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
        "-c", "SELECT json_build_object('version', version(), 'database', current_database(), "
              "'encoding', current_setting('server_encoding'), 'collation', datcollate) "
              "FROM pg_database WHERE datname = current_database()"],
        directory / "database", environment=environment)
    database = json.loads(database_raw)
    (directory / "reference.cjs").write_text(REFERENCE)
    reference_raw = execute([node, str(directory / "reference.cjs"),
                             str(ROOT / "third_party/json-logic-js/logic.js")],
                            directory / "reference", stdin=fixture_text, environment=environment)
    reference = json.loads(reference_raw)
    # A command argument avoids adding an I/O dependency to the native example.
    native_raw = execute([moon, "run", "-q", "src/examples/queryx", "--target", "native",
                          "--", fixture_text], directory / "native", environment=environment)
    native = json.loads(native_raw)
    if native.get("protocol") != "jsonlogic-queryx-check/1" or native.get("target") != "native":
        raise ValueError("unexpected MoonBit execution protocol")
    native_by_id = {query["id"]: query for query in native["queries"]}
    reference_by_id = {query["id"]: query for query in reference["queries"]}
    ids = [query["id"] for query in fixture["queries"]]
    if len(ids) != len(set(ids)) or set(ids) != set(native_by_id) or set(ids) != set(reference_by_id):
        raise ValueError("query IDs differ across fixture and evaluator outputs")
    report = {
        "status": "running",
        "fixture_sha256": hashlib.sha256(fixture_text.encode()).hexdigest(),
        "producer": fixture["producer"],
        "dependencies": {"json-logic-js": "2.0.5", "jaredzhou/queryx": "0.2.1",
                         "jaredzhou/foxql": "0.1.3"},
        "reference_sha256": hashlib.sha256(
            (ROOT / "third_party/json-logic-js/logic.js").read_bytes()).hexdigest(),
        "target": "native",
        "database": database,
        "sql_record_contract": {
            "text_column_collation": "C",
            "number_column_type": "INTEGER",
            "boolean_column_type": "BOOLEAN",
            "nullable": False,
            "table_lifetime": "TEMP tables in rolled-back transactions",
        },
        "query_count": len(ids),
        "record_evaluations": sum(len(query["data"]) for query in fixture["queries"]),
        "queries": [],
        "rule_rejections": native["rejections"],
        "record_rejections": native["record_rejections"],
        "negative_control": None,
        "limits": "Fixed RQB exports and rejection probes; complete nonnull Int32/string/bool "
                  "records, PostgreSQL C text collation. This is not a proof for all JSONLogic "
                  "or arbitrary SQL schemas/backends. No QueryX JSON serialization roundtrip.",
    }
    for index, query in enumerate(fixture["queries"]):
        output = native_by_id[query["id"]]
        expected = reference_by_id[query["id"]]["matched_ids"]
        matched = postgres_ids(query, output, output["parameters"], directory / f"query-{index:02d}",
                               psql, environment)
        entry = {"id": query["id"], "records": len(query["data"]), "reference_ids": expected,
                 "core_ids": sorted(output["core_ids"]), "queryx_ids": sorted(output["queryx_ids"]),
                 "postgres_ids": matched, "sql": output["sql"], "parameters": output["parameters"],
                 "expression_debug": output["expression_debug"]}
        entry["passed"] = expected == entry["core_ids"] == entry["queryx_ids"] == matched
        report["queries"].append(entry)
    for key, fixture_key in (("rule_rejections", "rejections"),
                             ("record_rejections", "record_rejections")):
        expected = {item["id"]: item for item in fixture[fixture_key]}
        actual_ids = [item["id"] for item in report[key]]
        if len(actual_ids) != len(set(actual_ids)) or set(actual_ids) != set(expected):
            raise ValueError(f"missing or duplicate {key} in native output")
        for item in report[key]:
            item["expected_reason"] = expected[item["id"]]["reason"]
            item["expected_error"] = expected[item["id"]]["expected_error"]
            diagnostic = item.get("error")
            required_kind = "InvalidRule" if key == "rule_rejections" else "InvalidRecord"
            expected_kind = {"invalid_rule": "InvalidRule", "invalid_record": "InvalidRecord"}[
                item["expected_error"]["kind"]]
            item["diagnostic_valid"] = (
                isinstance(diagnostic, dict)
                and diagnostic.get("kind") == required_kind == expected_kind
                and isinstance(diagnostic.get("path"), str)
                and diagnostic["path"] == item["expected_error"]["path"]
                and re.fullmatch(r"(?:/(?:[^~/]|~[01])*)*", diagnostic["path"]) is not None
                and isinstance(diagnostic.get("reason"), str) and bool(diagnostic["reason"])
                and isinstance(diagnostic.get("message"), str) and bool(diagnostic["message"])
                and diagnostic["reason"] in diagnostic["message"]
            )
    # Run one deliberately wrong parameter through the same real SQL evaluator.
    # The suite must detect it; search deterministic fixture order for an effective
    # change so a redundant comparison does not give a vacuous negative control.
    for query_index, query in enumerate(fixture["queries"]):
        output = native_by_id[query["id"]]
        expected = reference_by_id[query["id"]]["matched_ids"]
        for parameter_index, parameter in enumerate(output["parameters"]):
            changed = deepcopy(output["parameters"])
            changed[parameter_index] = mutate_parameter(parameter)
            actual = postgres_ids(query, output, changed,
                directory / f"negative-{query_index:02d}-{parameter_index:02d}", psql, environment)
            if actual != expected:
                report["negative_control"] = {
                    "id": query["id"], "parameter_index": parameter_index,
                    "original_parameters": output["parameters"], "modified_parameters": changed,
                    "reference_ids": expected, "postgres_ids": actual, "mismatch_detected": True,
                }
                break
        if report["negative_control"]:
            break
    passed = all(query["passed"] for query in report["queries"])
    passed = passed and all(item["rejected"] is True and item["diagnostic_valid"] for item in
                            report["rule_rejections"] + report["record_rejections"])
    passed = passed and bool(report["negative_control"])
    report["status"] = "passed" if passed else "failed"
    write_json(directory / "report.json", report)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, default=ROOT / "tests/queryx_fixture.json")
    parser.add_argument("--output", type=Path, default=ROOT / "output/queryx")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    directory = Path(tempfile.mkdtemp(prefix=timestamp + "-", dir=args.output.resolve()))
    try:
        report = run(args, directory)
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        write_json(directory / "report.json", {"status": "error", "error": str(error)})
        print(f"queryx verification failed: {error}\nEvidence: {directory}", file=sys.stderr)
        return 1
    write_json(args.output / "latest.json", {"report": str(directory / "report.json"),
                                            "status": report["status"]})
    print(f"QueryX integration: {report['status']}; {report['query_count']} queries, "
          f"{report['record_evaluations']} record evaluations, "
          f"{len(report['rule_rejections'])} rule rejections, "
          f"{len(report['record_rejections'])} record rejections; "
          f"negative control {'detected' if report['negative_control'] else 'NOT detected'}")
    print(f"Report: {directory / 'report.json'}")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
