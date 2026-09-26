#!/usr/bin/env python3
"""Run an observation package on multiple MoonBit backends and compare its transcripts."""
import argparse
from build_paths import cli_binary
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = ('native', 'js', 'wasm', 'wasm-gc')


def run(command, cwd, timeout):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {command!r}\n{result.stderr[-4000:]}')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=ROOT, help='module containing the observation package')
    parser.add_argument('--package', default='src/examples/text', help='observation executable, relative to project')
    parser.add_argument('--targets', nargs='+', choices=TARGETS, default=list(TARGETS), help='first target is the reference')
    parser.add_argument('--output', type=Path, help='parent directory for isolated run artifacts')
    parser.add_argument('--release', action='store_true')
    parser.add_argument('--timeout', type=float, default=120, help='timeout in seconds for each command')
    parser.add_argument('--abs-tol', default='0')
    parser.add_argument('--rel-tol', default='0')
    args = parser.parse_args()
    if len(args.targets) < 2 or len(set(args.targets)) != len(args.targets):
        parser.error('choose at least two distinct targets')
    if args.timeout <= 0:
        parser.error('timeout must be positive')
    moon = shutil.which('moon')
    if not moon:
        raise RuntimeError('moon is not on PATH; add your MoonBit bin directory')
    project = args.project.resolve()
    output = (args.output or (project / 'output' / 'casekit')).resolve()
    output.mkdir(parents=True, exist_ok=True)
    artifact_dir = Path(tempfile.mkdtemp(prefix='run-', dir=output))
    print(f'Artifacts: {artifact_dir}', flush=True)
    run([moon, 'build', '--target', 'native'], ROOT, args.timeout)
    comparator = cli_binary()
    transcripts = []
    for target in args.targets:
        command = [moon, 'run', '-q', '--target', target]
        if args.release:
            command.append('--release')
        command.append(args.package)
        result = run(command, project, args.timeout)
        path = artifact_dir / f'{target}.json'
        path.write_text(result.stdout, encoding='utf-8')
        transcripts.append(path)
        print(f'{target}: captured', flush=True)
    differences = False
    reference = transcripts[0]
    # A self comparison validates the reference even when other runs are malformed.
    for target, candidate in zip(args.targets, transcripts):
        command = [str(comparator), '--abs-tol', args.abs_tol, '--rel-tol', args.rel_tol, str(reference), str(candidate)]
        result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=args.timeout)
        (artifact_dir / f'{target}.report.txt').write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode not in (0, 1):
            raise RuntimeError(f'{target}: invalid transcript or comparison settings\n{result.stderr}')
        if result.returncode == 1:
            differences = True
        print(f'{args.targets[0]} → {target}: {result.stdout.strip()}', flush=True)
    return 1 if differences else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f'casekit runner: {error}', file=sys.stderr)
        sys.exit(2)
