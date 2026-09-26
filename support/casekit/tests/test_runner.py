"""End-to-end tests using temporary MoonBit programs with intentional output differences."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / 'tools/check_targets.py'


class RunnerTests(unittest.TestCase):
    def run_package(self, source):
        with tempfile.TemporaryDirectory(prefix='runner_fixture_', dir=ROOT / 'src') as package:
            package = Path(package)
            (package / 'moon.pkg').write_text('pkgtype(kind: "executable")\n')
            (package / 'main.mbt').write_text(source)
            with tempfile.TemporaryDirectory() as output:
                return subprocess.run(
                    [sys.executable, str(RUNNER), '--package', str(package.relative_to(ROOT)),
                     '--targets', 'native', 'js', '--output', output],
                    cwd=ROOT, capture_output=True, text=True, timeout=120,
                )

    def test_real_target_drift_is_reported(self):
        # Intentional fixture: it is not a compiler defect.
        result = self.run_package('''
#cfg(target="js")
fn value() -> Int { 2 }
#cfg(not(target="js"))
fn value() -> Int { 1 }
fn main {
  let doc : Json = {"casekit":1, "suite":"canary", "cases":[{"id":"value", "value":value().to_json()}]}
  println(doc.stringify())
}
''')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('value mismatch', result.stdout)
        self.assertIn('native → js', result.stdout)

    def test_non_protocol_stdout_is_an_error(self):
        result = self.run_package('fn main { println("debug log, not a transcript") }\n')
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('invalid transcript', result.stderr)

    def test_execution_timeout_is_an_error(self):
        with tempfile.TemporaryDirectory() as output:
            result = subprocess.run([sys.executable, str(RUNNER), '--timeout', '0.000001',
                                     '--output', output], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2)
        self.assertIn('timed out', result.stderr)


if __name__ == '__main__':
    unittest.main()
