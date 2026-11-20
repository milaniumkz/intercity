#!/usr/bin/env python3
"""Install an encrypted VTB sandbox configuration without printing credentials."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

def configure(payload_path, private_key_path, env_path):
    payload = json.loads(Path(payload_path).read_text())
    if payload.get('version') != 1 or payload.get('algorithm') != 'RSA-OAEP-256':
        raise ValueError('Unsupported encrypted configuration')
    key = str(private_key_path)
    public = subprocess.run(['openssl','pkey','-in',key,'-pubout','-outform','DER'],
                            check=True,capture_output=True).stdout
    if hashlib.sha256(public).hexdigest() != payload.get('keyFingerprint'):
        raise ValueError('Configuration key mismatch')
    cipher = base64.b64decode(payload['ciphertext'], validate=True)
    plain = subprocess.run(['openssl','pkeyutl','-decrypt','-inkey',key,
        '-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256'],
        input=cipher,check=True,capture_output=True).stdout
    config = json.loads(plain)
    username, password, enabled = config.get('userName'), config.get('password'), config.get('enabled')
    if not isinstance(username,str) or not re.fullmatch(r'[A-Za-z0-9._-]{1,96}-api',username):
        raise ValueError('Invalid API identity')
    if not isinstance(password,str) or not 1 <= len(password) <= 200 or any(x in password for x in '\r\n\0'):
        raise ValueError('Invalid credential')
    if type(enabled) is not bool:
        raise ValueError('Invalid activation state')
    credits = payload.get('walletCreditsEnabled', False)
    if type(credits) is not bool:
        raise ValueError('Invalid wallet credit state')
    target = Path(env_path)
    lines = target.read_text().splitlines()
    pattern = re.compile(r'^\s*VTB_SANDBOX_(?:ENABLED|USER_NAME|PASSWORD|PASSWORD_B64|WALLET_CREDITS_ENABLED)\s*=')
    lines = [line for line in lines if not pattern.match(line)]
    lines += ['VTB_SANDBOX_ENABLED='+str(enabled).lower(),
              'VTB_SANDBOX_WALLET_CREDITS_ENABLED='+str(credits).lower(),
              'VTB_SANDBOX_USER_NAME='+username,
              'VTB_SANDBOX_PASSWORD_B64='+base64.b64encode(password.encode()).decode()]
    fd, temporary = tempfile.mkstemp(prefix='.vtb-env-',dir=target.parent)
    try:
        with os.fdopen(fd,'w') as file:
            file.write('\n'.join(lines)+'\n')
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary,0o600)
        os.replace(temporary,target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

if __name__ == '__main__':
    try:
        if len(sys.argv) != 4:
            raise ValueError('Expected encrypted payload, server key, environment file')
        configure(*sys.argv[1:])
    except Exception:
        raise SystemExit('VTB sandbox credential installation failed; existing environment retained.')
    print('Installed VTB sandbox configuration: server-only credentials, no production bank endpoint.')
