"""Regression: manual checkout identity must win over the workflow event SHA."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseIdentityTest(unittest.TestCase):
    def test_bundle_stamp_and_manifest_match_checkout_not_event(self):
        checkout = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
        base = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD^'], text=True).strip()
        # Execute the real assignment without invoking builds, packaging, or deployment.
        stamp_assignment = next(line for line in (ROOT / 'scripts/build_vps_release_bundle.sh').read_text().splitlines()
                                if line.startswith('STAMP='))
        env = {**os.environ, 'ROOT_DIR': str(ROOT), 'GITHUB_SHA': '0' * 40}
        stamp = subprocess.check_output(['bash', '-c', stamp_assignment + '\nprintf %s "$STAMP"'],
                                        cwd='/tmp', env=env, text=True)
        self.assertEqual(stamp, checkout)
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory, 'manifest.json')
            subprocess.run(['python3', str(ROOT / 'scripts/vps_release_manifest.py'),
                            'create', base, str(manifest)], cwd=ROOT, env=env, check=True)
            self.assertEqual(json.loads(manifest.read_text())['releaseCommit'], stamp)


if __name__ == '__main__':
    unittest.main()
