import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'ci_flutter_paths', Path(__file__).resolve().parents[1] / 'ci_flutter_paths.py')
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)


class SelectionTests(unittest.TestCase):
    def test_path_scenarios(self):
        cases = [
            (['apps/admin_web/lib/main.dart'], (False, True)),
            (['apps/mobile_flutter/pubspec.lock'], (True, False)),
            (['apps/mobile_flutter/macos/Podfile'], (True, False)),
            (['packages/intercity_shared/lib/config.dart'], (True, True)),
            (['packages/flutter_tts_native/macos/plugin.swift'], (True, False)),
            (['packages/flutter_secure_storage_native/pubspec.yaml'], (True, False)),
            (['packages/future_package/lib/new.dart'], (True, True)),
            (['scripts/lib/flutter_release_helpers.sh'], (True, True)),
            (['.github/workflows/flutter_verify.yml'], (True, True)),
            (['scripts/ci_flutter_paths.py'], (True, True)),
            (['scripts/tests/test_ci_flutter_paths.py'], (True, True)),
            (['scripts/verify_flutter_apps.sh'], (True, True)),
            (['README.md', 'backend/src/main.ts', 'scripts/vps_ops.sh'], (False, False)),
            (['apps/admin_web/pubspec.yaml', 'apps/mobile_flutter/lib/main.dart'], (True, True)),
            ([], (False, False)),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual(ci.targets(paths), expected)

    def test_unknown_baseline_runs_all(self):
        for event, base in [('push', '0' * 40), ('push', ''), ('workflow_dispatch', 'abc')]:
            self.assertIsNone(ci.changed_paths(event, base, 'def'))
        with patch.object(ci.subprocess, 'run', side_effect=subprocess.CalledProcessError(128, 'git')):
            self.assertIsNone(ci.changed_paths('push', 'abc', 'def'))
        with tempfile.NamedTemporaryFile() as output:
            with patch.dict(os.environ, {'CI_EVENT': 'workflow_dispatch', 'GITHUB_OUTPUT': output.name}):
                ci.main()
            self.assertEqual(Path(output.name).read_text(), 'mobile=1\nadmin=1\n')

    def test_real_git_pr_push_rename_and_delete(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], stderr=subprocess.DEVNULL).decode().strip()
            def commit():
                git('add', '.')
                git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture')
                return git('rev-parse', 'HEAD')
            def write(name):
                p = Path(directory, name)
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('fixture')
            git('init', '-q')
            write('apps/mobile_flutter/lib/old.dart')
            base = commit()
            git('checkout', '-qb', 'feature')
            git('mv', 'apps/mobile_flutter/lib/old.dart', 'old.dart')
            renamed = commit()
            git('checkout', '-qb', 'base-advanced', base)
            write('apps/admin_web/lib/main.dart')
            advanced = commit()
            old_cwd = os.getcwd()
            try:
                os.chdir(directory)
                # PR compares merge base: unrelated base-branch admin edit excluded.
                self.assertEqual(ci.targets(ci.changed_paths('pull_request', advanced, renamed)), (True, False))
                # Push compares both endpoints, including deleted/moved source paths.
                self.assertEqual(ci.targets(ci.changed_paths('push', advanced, renamed)), (True, True))
                self.assertEqual(ci.targets(ci.changed_paths('push', base, renamed)), (True, False))
            finally:
                os.chdir(old_cwd)


if __name__ == '__main__':
    unittest.main()
