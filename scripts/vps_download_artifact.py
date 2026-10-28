#!/usr/bin/env python3
"""Receive a short-lived artifact URL on stdin; verify before extracting a bundle."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import urllib.parse
import urllib.request
import zipfile


def main():
    data = json.load(sys.stdin)
    sha, digest = data['sha'], data['digest']
    if not re.fullmatch(r'[a-f0-9]{40}', sha) or not re.fullmatch(r'sha256:[a-f0-9]{64}', digest):
        raise ValueError('Invalid artifact identity')
    url = urllib.parse.urlparse(data['url'])
    if url.scheme != 'https' or not url.hostname or not url.hostname.endswith(('.blob.core.windows.net', '.actions.githubusercontent.com', '.githubusercontent.com')):
        raise ValueError('Invalid artifact host')
    os.umask(0o077)
    archive = Path('/tmp') / f'intercity-artifact-{sha}.zip'
    bundle = Path('/tmp') / f'intercity-vps-{sha}.tar.gz'
    temporary = bundle.with_suffix('.download')
    checksum, size = hashlib.sha256(), 0
    try:
        with urllib.request.urlopen(data['url'], timeout=90) as response, archive.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > 512 * 1024 * 1024:
                    raise ValueError('Artifact too large')
                checksum.update(chunk)
                output.write(chunk)
        if checksum.hexdigest() != digest.split(':')[1]:
            raise ValueError('Artifact checksum mismatch')
        with zipfile.ZipFile(archive) as package:
            if package.namelist() != [bundle.name] or package.getinfo(bundle.name).file_size > 512 * 1024 * 1024:
                raise ValueError('Unexpected bundle layout')
            with package.open(bundle.name) as source, temporary.open('wb') as output:
                shutil.copyfileobj(source, output, 1024 * 1024)
        temporary.replace(bundle)
        config = Path('/tmp') / f'intercity-yandex-{sha}.json'
        config.write_text(json.dumps({'key': data.get('key', ''), 'firebase': data.get('firebase', '')}))
        print(f'Verified HTTPS artifact: {size} bytes, SHA-256 matched')
    finally:
        archive.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Never include a signed download URL or provider credentials in logs.
        print('Artifact download or verification failed', file=sys.stderr)
        sys.exit(1)
