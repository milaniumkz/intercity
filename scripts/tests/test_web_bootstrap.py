"""Exercise the real release-packaging code with both Flutter script formats."""
import pathlib, tempfile, subprocess, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class BootstrapTest(unittest.TestCase):
 def test_admin_has_one_loader_with_bare_or_empty_async(self):
  script=(ROOT/'scripts/build_vps_release_bundle.sh').read_text().split("<<'PYWEB'\n",1)[1].split('\nPYWEB',1)[0]
  for attr in ['async', 'async=""']:
   with self.subTest(attr=attr), tempfile.TemporaryDirectory() as tmp:
    root=pathlib.Path(tmp);(root/'mobile').mkdir();(root/'admin').mkdir()
    (root/'mobile/index.html').write_text('<head><script id="intercity-cache-reset">window.loader=true;</script></head>')
    (root/'mobile/flutter_service_worker.js').write_text('// retired')
    index=root/'admin/index.html';index.write_text(f'<head></head><body><script src="flutter_bootstrap.js" {attr}></script></body>')
    for _ in range(2): subprocess.run(['python3','-',str(root)],input=script,text=True,check=True)
    text=index.read_text();self.assertEqual(text.count('intercity-cache-reset'),1);self.assertNotIn('src="flutter_bootstrap.js"',text)
if __name__=='__main__': unittest.main()
