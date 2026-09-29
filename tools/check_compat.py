#!/usr/bin/env python3
"""Check JSONLogic results on every MoonBit target against pinned json-logic-js."""
import argparse
from decimal import Decimal
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('native', 'js', 'wasm', 'wasm-gc')
SUITE = 'jsonlogic-2.0.5'
MISSING = object()


def run(command):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f'{command!r} failed ({result.returncode})\n{result.stdout}\n{result.stderr}')
    return result.stdout


def reject_constant(value):
    raise ValueError(f'non-JSON number: {value}')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def load_results(path):
    document = json.loads(path.read_text(), parse_int=Decimal, parse_float=Decimal,
                          parse_constant=reject_constant, object_pairs_hook=unique_object)
    if not isinstance(document, dict) or document.get('suite') != SUITE:
        raise ValueError(f'{path}: wrong or missing suite')
    rows = document.get('cases')
    if not isinstance(rows, list) or not rows:
        raise ValueError(f'{path}: cases must be a nonempty array')
    results = {}
    for row in rows:
        if (not isinstance(row, dict) or set(row) != {'id', 'value'}
                or not isinstance(row['id'], str) or not row['id']):
            raise ValueError(f'{path}: invalid case record')
        if row['id'] in results:
            raise ValueError(f'{path}: duplicate case ID {row["id"]}')
        results[row['id']] = row['value']
    return results


def difference(expected, actual, path=''):
    """Return the first differing JSON Pointer within a single fixture result."""
    if type(expected) is not type(actual):
        return path
    if isinstance(expected, dict):
        for key in sorted(expected.keys() | actual.keys()):
            child = path + '/' + key.replace('~', '~0').replace('/', '~1')
            found = difference(expected.get(key, MISSING), actual.get(key, MISSING), child)
            if found is not None:
                return found
    elif isinstance(expected, list):
        if len(expected) != len(actual):
            return path
        for index, (left, right) in enumerate(zip(expected, actual)):
            found = difference(left, right, f'{path}/{index}')
            if found is not None:
                return found
    elif expected != actual:
        return path
    return None


def compare(expected, actual):
    mismatches = []
    for case_id in sorted(expected.keys() | actual.keys()):
        path = difference(expected.get(case_id, MISSING), actual.get(case_id, MISSING))
        if path is not None:
            mismatches.append({'case': case_id, 'path': path})
    return {'suite': SUITE, 'matches': not mismatches, 'differences': mismatches}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targets', choices=TARGETS, nargs='+', default=list(TARGETS))
    args = parser.parse_args()
    run([sys.executable, 'tools/generate_cases.py', '--check'])
    parent = ROOT / 'output/compat'
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    expected = output / 'reference.json'
    expected.write_text(run(['node', 'tools/reference.cjs']))
    reference = load_results(expected)
    print(f'Artifacts: {output}', flush=True)
    for target in args.targets:
        actual = output / f'{target}.json'
        actual.write_text(run(['moon', 'run', '-q', '--target', target, 'compat/src']))
        report = compare(reference, load_results(actual))
        (output / f'{target}.report.json').write_text(json.dumps(report, indent=2))
        if not report['matches']:
            raise RuntimeError(f'{target}: results differ\n{json.dumps(report, indent=2)}')
        print(f'{target}: {len(reference)} cases match json-logic-js 2.0.5', flush=True)
    # Exercise the same file loading and comparison path with deliberately wrong output.
    tampered = output / 'negative-control.json'
    document = json.loads(expected.read_text())
    document['cases'][0]['value'] = {'deliberate_mismatch': True}
    tampered.write_text(json.dumps(document))
    report = compare(reference, load_results(tampered))
    (output / 'negative-control.report.json').write_text(json.dumps(report, indent=2))
    if report['matches']:
        raise RuntimeError('comparison failed to reject a deliberately changed result')
    print('Negative control: altered result rejected', flush=True)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
