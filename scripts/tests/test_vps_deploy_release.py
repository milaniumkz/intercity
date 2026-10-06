import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
OLD = 'a' * 40
NEW = 'b' * 40


class DeployTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name).resolve()
        self.app = self.path / 'server'
        self.old = self.app / 'releases' / OLD
        (self.old / 'infra/vps').mkdir(parents=True)
        (self.old / 'source.txt').write_text('previous source')
        (self.old / 'infra/vps/.env').write_text('TEST_ONLY=1\n')
        (self.app / 'current').symlink_to(self.old)
        (self.app / 'current_commit').write_text(OLD)
        (self.app / 'shared/uploads').mkdir(parents=True)
        (self.app / 'shared/uploads/test.txt').write_text('upload backup fixture')
        (self.app / 'shared/.env').write_text('TEST_ONLY=1\n')
        staged = self.path / 'bundle/intercity'
        (staged / 'scripts').mkdir(parents=True)
        (staged / 'infra/vps').mkdir(parents=True)
        (staged / 'scripts/vps_release_manifest.py').write_bytes((ROOT / 'scripts/vps_release_manifest.py').read_bytes())
        (staged / '.release-manifest.json').write_text(json.dumps({
            'baseCommit': OLD, 'releaseCommit': NEW,
            'files': {'source.txt': hashlib.sha256(b'previous source').hexdigest()},
        }))
        self.bundle = self.path / 'bundle.tar.gz'
        with tarfile.open(self.bundle, 'w:gz') as archive:
            archive.add(staged, arcname='intercity')
        bin_dir = self.path / 'bin'
        bin_dir.mkdir()
        docker = bin_dir / 'docker'
        docker.write_text('''#!/usr/bin/env bash
set -eu
printf '%s|%s\n' "$PWD" "$*" >> "$CALL_LOG"
if [[ "$1" == inspect ]]; then
  if [[ "$*" == *'{{.Image}}'* ]]; then echo sha256:previous; else echo vps; fi
elif [[ "$1" == exec ]]; then
  [[ "$SCENARIO" != backup_failure ]] || exit 1
  echo '-- PostgreSQL database dump complete'
elif [[ "$*" == *' run '* && "$SCENARIO" == migration_failure ]]; then
  exit 1
fi
''')
        curl = bin_dir / 'curl'
        curl.write_text('''#!/usr/bin/env bash
set -eu
[[ "$SCENARIO" != health_failure ]] || exit 1
if [[ "$*" == *geo/cities* ]]; then echo '[]'; else printf '{"commit":"%s"}\n' "$NEW_COMMIT"; fi
''')
        docker.chmod(0o755)
        curl.chmod(0o755)
        self.log = self.path / 'calls.log'
        self.env = {**os.environ, 'PATH': str(bin_dir) + ':' + os.environ['PATH'],
                    'APP_ROOT': str(self.app), 'CALL_LOG': str(self.log), 'NEW_COMMIT': NEW}

    def run_release(self, scenario='success'):
        result = subprocess.run(['bash', str(ROOT / 'scripts/vps_deploy_release.sh'), str(self.bundle), NEW],
                                env={**self.env, 'SCENARIO': scenario}, capture_output=True, text=True)
        calls = self.log.read_text() if self.log.exists() else ''
        return result, calls

    def test_backup_and_migrations_precede_switch(self):
        result, calls = self.run_release()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.app / 'current_commit').read_text().strip(), NEW)
        backup = next((self.app / 'backups').iterdir())
        self.assertTrue((backup / 'postgres.sql').is_file())
        self.assertTrue((backup / 'uploads.tar.gz').is_file())
        self.assertLess(calls.index('pg_dump'), calls.index(' build backend'))
        self.assertLess(calls.index('migrate deploy'), calls.index(' up -d'))

    def test_failed_backup_keeps_old_release(self):
        result, calls = self.run_release('backup_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(' build backend', calls)
        self.assertEqual((self.app / 'current').resolve(), self.old)

    def test_source_drift_stops_before_database_changes(self):
        (self.old / 'source.txt').write_text('server hotfix')
        result, calls = self.run_release()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('pg_dump', calls)
        self.assertNotIn('migrate deploy', calls)

    def test_failed_migration_never_starts_new_backend(self):
        result, calls = self.run_release('migration_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(' up -d', calls)
        self.assertEqual((self.app / 'current').resolve(), self.old)

    def test_failed_live_check_restores_previous_image_and_release(self):
        result, calls = self.run_release('health_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('tag sha256:previous intercity-backend:prod', calls)
        self.assertIn(str(self.old / 'infra/vps') + '|compose', calls)
        self.assertEqual((self.app / 'current_commit').read_text().strip(), OLD)
        self.assertEqual((self.app / 'current').resolve(), self.old)


if __name__ == '__main__':
    unittest.main()
