"""Locate the CLI in a standalone module or a MoonBit workspace build."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

def cli_binary():
    for directory in (ROOT, *ROOT.parents):
        if (directory / 'moon.work').exists():
            return directory / '_build/native/debug/build/kaigeliang/casekit/cli/cli.exe'
    return ROOT / '_build/native/debug/build/cli/cli.exe'
