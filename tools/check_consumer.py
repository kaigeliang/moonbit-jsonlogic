#!/usr/bin/env python3
"""Verify the documented source-workspace integration in an external application."""
import json
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='jsonlogic-consumer-') as directory:
    app = Path(directory)
    (app / 'src').mkdir()
    (app / 'moon.mod').write_text('name = "example/jsonlogic-consumer"\nversion = "0.1.0"\nsource = "src"\nimport { "kaigeliang/jsonlogic@0.1.0" }\n')
    (app / 'moon.work').write_text('members = [".", ' + json.dumps(str(ROOT)) + ']\n')
    (app / 'src/moon.pkg').write_text('import { "kaigeliang/jsonlogic" @logic }\noptions("is-main": true)\n')
    (app / 'src/main.mbt').write_text('''fn main raise {
  let rule : Json = { ">=": [{ "var": "age" }, 18] }
  let result = @logic.apply(rule, { "age": 22 })
  assert_eq(result, true)
  println("consumer-ok")
}
''')
    for target in ('native', 'js'):
        result = subprocess.run(['moon', 'run', '-q', 'src', '--target', target], cwd=app, capture_output=True, text=True, timeout=120)
        if result.returncode or result.stdout.strip() != 'consumer-ok':
            raise SystemExit(f'{target}: external consumer failed\n{result.stdout}\n{result.stderr}')
        print(f'{target}: external consumer passed using the JSONLogic core package')
    # Import the public native adapter from a separate application, not an
    # in-repository example. Its Expr is the actual upstream QueryX type.
    (app / 'moon.mod').write_text('name = "example/jsonlogic-consumer"\nversion = "0.1.0"\nsource = "src"\nimport { "kaigeliang/jsonlogic@0.1.0", "jaredzhou/queryx@0.2.1" }\n')
    (app / 'src/moon.pkg').write_text('import { "kaigeliang/jsonlogic/queryx" @adapter, "jaredzhou/queryx" @qx }\nsupported_targets = "native"\noptions("is-main": true)\n')
    (app / 'src/main.mbt').write_text('''fn main raise {
  let fields = [@adapter.Field::{ name: "age", kind: @adapter.FieldType::Number }]
  @adapter.validate_record({ "age": 22 }, fields)
  let expr = @adapter.import_filter({ ">=": [{ "var": "age" }, 18] }, fields)
  let values : Map[String, @qx.Value] = Map([("age", @qx.Value::Int(22L))])
  assert_true(expr.eval(values))
  try {
    let _ = @adapter.import_filter({ ">=": [{ "var": "age" }, "18"] }, fields)
    fail("expected the public adapter to reject coercion")
  } catch {
    @adapter.InvalidRule(_, _) => ()
    _ => fail("wrong public adapter error")
  }
  println("queryx-consumer-ok")
}
''')
    result = subprocess.run(['moon', 'run', '-q', 'src', '--target', 'native'], cwd=app, capture_output=True, text=True, timeout=120)
    if result.returncode or result.stdout.strip() != 'queryx-consumer-ok':
        raise SystemExit(f'native: external QueryX consumer failed\n{result.stdout}\n{result.stderr}')
    print('native: external application imported the QueryX adapter and rejected coercion')
