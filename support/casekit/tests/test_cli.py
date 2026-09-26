"""Exercise the built native CLI's exit codes and reports without external packages."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_paths import cli_binary
BINARY = cli_binary()


def transcript(value):
    return json.dumps({'casekit': 1, 'suite': 'cli', 'cases': [{'id': 'value', 'value': value}]})


class CliTests(unittest.TestCase):
    def run_compare(self, left, right, *options):
        with tempfile.TemporaryDirectory() as directory:
            a, b = Path(directory) / 'a.json', Path(directory) / 'b.json'
            a.write_text(left, encoding='utf-8')
            b.write_text(right, encoding='utf-8')
            return subprocess.run([str(BINARY), *options, str(a), str(b)], capture_output=True, text=True)

    def test_match(self):
        result = self.run_compare(transcript({'a': [1, 2]}), transcript({'a': [1, 2]}))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('MATCH', result.stdout)

    def test_difference_report(self):
        result = self.run_compare(transcript({'a': [1]}), transcript({'a': [2]}), '--json')
        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['differences'][0]['path'], '/a/0')
        self.assertEqual(report['differences'][0]['expected'], 1)
        self.assertEqual(report['differences'][0]['actual'], 2)

    def test_invalid_transcript(self):
        result = self.run_compare('{', transcript(1))
        self.assertEqual(result.returncode, 2)
        self.assertIn('invalid JSON', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_numeric_tolerance(self):
        result = self.run_compare(transcript(1), transcript(1.00001), '--abs-tol', '0.001')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('tolerance', result.stdout)

    def test_invalid_tolerance_and_missing_file(self):
        result = self.run_compare(transcript(1), transcript(1), '--abs-tol', '-1')
        self.assertEqual(result.returncode, 2)
        result = subprocess.run([str(BINARY), '/does-not-exist-casekit', '/does-not-exist-casekit'], capture_output=True)
        self.assertEqual(result.returncode, 2)


if __name__ == '__main__':
    unittest.main()
