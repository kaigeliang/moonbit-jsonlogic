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
        print(f'{target}: external consumer passed without CaseKit workspace membership')
