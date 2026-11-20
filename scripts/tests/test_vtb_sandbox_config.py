import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('vtb_config',Path(__file__).parents[1]/'configure_vtb_sandbox.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class VtbConfigTest(unittest.TestCase):
    def test_encrypted_config_is_atomic_preserves_other_settings_and_quotes(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);key=root/'key.pem';env=root/'.env';payload=root/'sealed.json'
            subprocess.run(['openssl','genpkey','-algorithm','RSA','-pkeyopt','rsa_keygen_bits:2048','-out',str(key)],check=True,capture_output=True)
            public=subprocess.run(['openssl','pkey','-in',str(key),'-pubout','-outform','DER'],check=True,capture_output=True).stdout
            password="fixture-$-'special"
            plain=json.dumps({'userName':'fixture-api','password':password,'enabled':True}).encode()
            encrypted=subprocess.run(['openssl','pkeyutl','-encrypt','-inkey',str(key),'-pkeyopt','rsa_padding_mode:oaep','-pkeyopt','rsa_oaep_md:sha256'],input=plain,check=True,capture_output=True).stdout
            data={'version':1,'algorithm':'RSA-OAEP-256','keyFingerprint':hashlib.sha256(public).hexdigest(),'ciphertext':base64.b64encode(encrypted).decode()}
            payload.write_text(json.dumps(data));env.write_text('KASSA24_LOGIN=keep\nVTB_SANDBOX_PASSWORD=stale\nOTHER=unchanged\n')
            module.configure(payload,key,env)
            text=env.read_text()
            self.assertIn('KASSA24_LOGIN=keep',text);self.assertIn('OTHER=unchanged',text)
            self.assertNotIn(password,text);self.assertNotIn('PASSWORD=stale',text)
            self.assertIn(base64.b64encode(password.encode()).decode(),text)
            self.assertEqual(os.stat(env).st_mode & 0o777,0o600)
            self.assertIn('VTB_SANDBOX_WALLET_CREDITS_ENABLED=false',text)
            data['walletCreditsEnabled']=True;payload.write_text(json.dumps(data))
            module.configure(payload,key,env)
            self.assertIn('VTB_SANDBOX_WALLET_CREDITS_ENABLED=true',env.read_text())
            before=env.read_bytes()
            data['walletCreditsEnabled']='true';payload.write_text(json.dumps(data))
            with self.assertRaises(ValueError):module.configure(payload,key,env)
            self.assertEqual(before,env.read_bytes())
            data['walletCreditsEnabled']=True
            data['keyFingerprint']='wrong';payload.write_text(json.dumps(data))
            before=env.read_bytes()
            with self.assertRaises(ValueError):module.configure(payload,key,env)
            self.assertEqual(before,env.read_bytes())
if __name__=='__main__':unittest.main()
