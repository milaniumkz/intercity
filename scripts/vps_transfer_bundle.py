#!/usr/bin/env python3
"""Transfer a release in bounded, resumable SSH chunks; verify before publishing."""
import concurrent.futures
import hashlib
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import time


def transfer(bundle, sha):
    if not re.fullmatch(r'[a-f0-9]{40}', sha):
        raise ValueError('Invalid release SHA')
    target = os.environ['VPS_USER'] + '@' + os.environ['VPS_HOST']
    remote = '/tmp/intercity-transfer-' + sha
    options = ['-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20', '-o', 'ServerAliveInterval=10', '-o', 'ServerAliveCountMax=3']
    def ssh(command):
        return subprocess.run(['ssh', *options, target, command], check=True, capture_output=True, text=True, timeout=90)
    ssh('mkdir -p ' + remote + ' && chmod 700 ' + remote)
    existing = ssh('cd ' + remote + ' && (sha256sum chunk-* 2>/dev/null || true)').stdout
    hashes = {}
    for line in existing.splitlines():
        match = re.fullmatch(r'([a-f0-9]{64})  (chunk-[0-9]{4})', line)
        if match:
            hashes[match[2]] = match[1]
    with tempfile.TemporaryDirectory(prefix='intercity-transfer-') as temporary:
        parts, total = [], hashlib.sha256()
        with Path(bundle).open('rb') as source:
            while block := source.read(1024 * 1024):
                part = Path(temporary) / f'chunk-{len(parts):04d}'
                part.write_bytes(block)
                parts.append((part, hashlib.sha256(block).hexdigest()))
                total.update(block)
        if not parts or len(parts) > 512:
            raise ValueError('Invalid bundle size')
        def upload(item):
            part, digest = item
            if hashes.get(part.name) == digest:
                print('Reusing ' + part.name, flush=True)
                return
            for attempt in range(4):
                try:
                    subprocess.run(['scp', *options, str(part), target + ':' + remote + '/' + part.name], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=90)
                    print('Transferred ' + part.name, flush=True)
                    return
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                    if attempt == 3:
                        raise RuntimeError('Chunk transfer failed: ' + part.name) from None
                    time.sleep(2 * (attempt + 1))
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as workers:
            list(workers.map(upload, parts))
        names = ' '.join(part.name for part, _ in parts)
        destination = '/tmp/intercity-vps-' + sha + '.tar.gz'
        check = shlex.quote(total.hexdigest() + '  ' + destination + '.new')
        ssh('cd ' + remote + ' && cat ' + names + ' > ' + destination + '.new && printf "%s\\n" ' + check + ' | sha256sum -c - && mv ' + destination + '.new ' + destination)
        print(f'Verified complete bundle: {len(parts)} chunks, SHA-256 matched', flush=True)


if __name__ == '__main__':
    transfer(sys.argv[1], sys.argv[2])
