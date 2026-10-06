#!/usr/bin/env python3
"""Select Flutter targets using local git history, without GitHub API permissions."""
import os
import subprocess


COMMON_FILES = {
    '.github/workflows/flutter_verify.yml',
    'scripts/ci_flutter_paths.py',
    'scripts/tests/test_ci_flutter_paths.py',
    'scripts/verify_flutter_apps.sh',
    'scripts/lib/flutter_release_helpers.sh',
    'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    '.fvmrc', '.flutter-version', '.tool-versions',
}


def targets(paths):
    mobile = admin = False
    for path in paths:
        if path in COMMON_FILES or path.startswith('.fvm/'):
            mobile = admin = True
        elif path.startswith('packages/'):
            # Known mobile-only plugins; unknown future packages run both apps.
            mobile = True
            if not path.startswith(('packages/flutter_tts_native/',
                                    'packages/flutter_secure_storage_native/')):
                admin = True
        elif path.startswith('apps/mobile_flutter/'):
            mobile = True
        elif path.startswith('apps/admin_web/'):
            admin = True
    return mobile, admin


def changed_paths(event, base, head):
    if event not in ('pull_request', 'push') or not base or not head or set(base) == {'0'}:
        return None  # Unknown baseline: run all checks, never silently skip.
    comparison = f'{base}...{head}' if event == 'pull_request' else f'{base}..{head}'
    try:
        result = subprocess.run(
            ['git', 'diff', '--name-only', '--no-renames', '-z', comparison, '--'],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
    except subprocess.CalledProcessError:
        print('Diff unavailable; verifying both Flutter apps.')
        return None
    return result.stdout.decode('utf-8', errors='surrogateescape').split('\0')


def main():
    paths = changed_paths(os.environ.get('CI_EVENT', ''),
                          os.environ.get('CI_BASE', ''), os.environ.get('CI_HEAD', ''))
    mobile, admin = (True, True) if paths is None else targets(paths)
    output = f'mobile={int(mobile)}\nadmin={int(admin)}\n'
    print(output, end='')
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as stream:
        stream.write(output)


if __name__ == '__main__':
    main()
