#!/usr/bin/env python3
"""Compare a release with the exact source currently running on the VPS."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys


def git(*args):
    return subprocess.check_output(['git', *args])


def create(base, destination):
    release = git('rev-parse', 'HEAD').decode().strip()
    paths = git('diff', '--name-only', '--no-renames', base, release).decode().splitlines()
    # Older releases copied a build-mutated lockfile. These audited overrides
    # still require an exact hash for one specific published commit and path.
    baseline_path = Path(__file__).with_name('production_source_baselines.json')
    overrides = json.loads(baseline_path.read_text()).get(base, {}) if baseline_path.exists() else {}
    files = {}
    for path in paths:
        if path.startswith(('.github/', 'output/', 'infra/vps/web/')):
            continue
        old = subprocess.run(['git', 'show', f'{base}:{path}'], capture_output=True)
        files[path] = overrides.get(path, hashlib.sha256(old.stdout).hexdigest() if old.returncode == 0 else None)
    Path(destination).write_text(json.dumps({'baseCommit': base, 'releaseCommit': release, 'files': files}, indent=2))


def check(manifest_path, current, expected_release):
    manifest = json.loads(Path(manifest_path).read_text())
    current = Path(current).resolve()
    if manifest['releaseCommit'] != expected_release:
        raise ValueError('Bundle commit differs from requested release')
    marker = (current.parent.parent / 'current_commit').read_text().strip()
    if marker != manifest['baseCommit']:
        raise ValueError(f'Production changed: expected {manifest["baseCommit"]}, found {marker}')
    for name, expected in manifest['files'].items():
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts:
            raise ValueError('Invalid source path in release manifest')
        target = current / path
        if expected is None:
            if target.exists():
                raise ValueError(f'Unexpected existing source file: {name}')
        elif not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Production source differs from baseline: {name}')
    print(f'Production source verified: {len(manifest["files"])} changed paths, base {marker}')


if __name__ == '__main__':
    if sys.argv[1] == 'create':
        create(*sys.argv[2:])
    elif sys.argv[1] == 'check':
        check(*sys.argv[2:])
    else:
        raise ValueError('Expected create or check')
