#!/usr/bin/env python3
"""Fetch the pinned MIT BRouter runtime, never a public routing API."""
import hashlib
import io
from pathlib import Path
import sys
import urllib.request
import zipfile
VERSION = '1.7.10'
SHA256 = '023fec3ba997758e8cd7ab9e1bae52e962af3f00b57683e3de86b84ffad01532'
URL = f'https://github.com/abrensch/brouter/releases/download/v{VERSION}/brouter-{VERSION}.zip'
def prepare(root):
    with urllib.request.urlopen(URL, timeout=60) as response:
        data = response.read(10 * 1024 * 1024)
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError('BRouter release checksum mismatch')
    archive = zipfile.ZipFile(io.BytesIO(data))
    root = Path(root); root.mkdir(parents=True, exist_ok=True)
    prefix = f'brouter-{VERSION}/'
    (root / 'brouter.jar').write_bytes(archive.read(prefix + f'brouter-{VERSION}-all.jar'))
    profiles = root / 'profiles2'; profiles.mkdir(exist_ok=True)
    for name in ['lookups.dat', 'car-fast-nocost.brf']:
        content = archive.read(prefix + 'profiles2/' + name)
        if name.endswith('.brf') and (b'assign add_beeline         = false' not in content or b'assign validForCars        = true' not in content):
            raise ValueError('Unexpected car profile: refuse non-road routing')
        (profiles / name).write_bytes(content)
    print(f'BRouter {VERSION} runtime verified ({SHA256})')
if __name__ == '__main__':
    prepare(sys.argv[1])
