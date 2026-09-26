#!/usr/bin/env python3
"""Compare every MoonBit target with pinned json-logic-js, using CaseKit."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('native', 'js', 'wasm', 'wasm-gc')

def run(command, *, check=True):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    if check and result.returncode:
        raise RuntimeError(f'{command!r} failed ({result.returncode})\n{result.stdout}\n{result.stderr}')
    return result

def compare(expected, actual):
    return run(['moon', 'run', '-q', '--target', 'native', 'support/casekit/src/cli', '--', '--json', str(expected), str(actual)], check=False)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targets', choices=TARGETS, nargs='+', default=list(TARGETS))
    args = parser.parse_args()
    run([sys.executable, 'tools/generate_cases.py', '--check'])
    parent = ROOT / 'output/compat'; parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    expected = output / 'reference.json'
    expected.write_text(run(['node', 'tools/reference.cjs']).stdout)
    reference = json.loads(expected.read_text())
    print(f'Artifacts: {output}', flush=True)
    for target in args.targets:
        actual = output / f'{target}.json'
        actual.write_text(run(['moon', 'run', '-q', '--target', target, 'compat/src']).stdout)
        result = compare(expected, actual)
        (output / f'{target}.report.json').write_text(result.stdout)
        if result.returncode:
            raise RuntimeError(f'{target}: CaseKit comparison failed ({result.returncode})\n{result.stdout}\n{result.stderr}')
        print(f'{target}: {len(reference["cases"])} cases match json-logic-js 2.0.5', flush=True)
    # A deliberate corruption must be rejected: prevents accidentally bypassing the gate.
    reference['cases'][0]['value'] = {'deliberate_mismatch': True}
    tampered = output / 'negative-control.json'; tampered.write_text(json.dumps(reference))
    rejection = compare(expected, tampered)
    if rejection.returncode != 1:
        raise RuntimeError('CaseKit failed to reject the deliberately changed result')
    (output / 'negative-control.report.json').write_text(rejection.stdout)
    print('Negative control: altered result rejected', flush=True)

if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr); sys.exit(1)
