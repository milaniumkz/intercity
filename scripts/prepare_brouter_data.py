#!/usr/bin/env python3
"""Install the reviewed routing snapshot with one download at a time and a disk reserve."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time
import urllib.request

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def prepare(manifest_path, destination):
    manifest = json.loads(Path(manifest_path).read_text())
    if manifest['source'] != 'https://brouter.de/brouter/segments4/':
        raise ValueError('Unexpected routing data source')
    root = Path(destination); root.mkdir(parents=True, exist_ok=True); root.chmod(0o755)
    pending = []
    for entry in manifest['files']:
        name, size, sha = entry['name'], entry['bytes'], entry['sha256']
        if not re.fullmatch(r'[EW]\d{1,3}_[NS]\d{1,2}\.rd5', name) or not re.fullmatch(r'[a-f0-9]{64}', sha) or not 0 < size <= 256*1024*1024:
            raise ValueError('Invalid routing manifest entry')
        path = root / name
        if not (path.is_file() and path.stat().st_size == size and digest(path) == sha):
            pending.append(entry)
    required = sum(entry['bytes'] for entry in pending) + 8 * 1024**3
    if shutil.disk_usage(root).free < required:
        raise ValueError('Not enough disk space: require routing download plus 8 GiB reserve')
    # Validate available memory before adding a service on the existing server.
    mem = Path('/proc/meminfo').read_text()
    available = int(re.search(r'^MemAvailable:\s+(\d+)', mem, re.M)[1]) * 1024
    if available < 768*1024**2:
        raise ValueError('Not enough available RAM for the bounded routing service')
    print(f'Routing data: {len(pending)} files to download, {sum(e["bytes"] for e in pending)} bytes; disk and RAM checked', flush=True)
    for index, entry in enumerate(pending):
        path = root / entry['name']; temporary = path.with_suffix('.part')
        for attempt in range(3):
            try:
                request = urllib.request.Request(manifest['source'] + entry['name'], headers={'User-Agent':'InterCity routing snapshot installer/1.0'})
                with urllib.request.urlopen(request, timeout=60) as response, temporary.open('wb') as target:
                    remaining = entry['bytes'] + 1
                    while remaining:
                        chunk = response.read(min(1024*1024, remaining))
                        if not chunk: break
                        target.write(chunk); remaining -= len(chunk)
                if temporary.stat().st_size != entry['bytes'] or digest(temporary) != entry['sha256']:
                    raise ValueError('Routing snapshot changed or download corrupted')
                temporary.chmod(0o644); os.replace(temporary, path)
                break
            except Exception:
                temporary.unlink(missing_ok=True)
                if attempt == 2: raise
                time.sleep(2 * (attempt+1))
        if (index+1) % 25 == 0: print(f'Routing download {index+1}/{len(pending)}', flush=True)
    (root.parent / 'installed-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'Routing snapshot verified: {len(manifest["files"])} files, {manifest["bytes"]} bytes', flush=True)
if __name__ == '__main__':
    prepare(*sys.argv[1:])
