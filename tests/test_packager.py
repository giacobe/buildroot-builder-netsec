import gzip
import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest
from types import SimpleNamespace
import sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('packager', Path(__file__).parents[1] / 'scripts/package_rootfs_payload.py')
p = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = p
spec.loader.exec_module(p)
class PackagingTests(unittest.TestCase):
    def test_overlay_preserves_device_and_permissions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fields = dict(ino=1, mode=stat.S_IFCHR | 0o600, uid=0, gid=0, nlink=1, mtime=0, devmajor=0, devminor=0, rdevmajor=5, rdevminor=1, check=0)
            device = p.Entry('dev/console', fields, b'')
            with gzip.open(root / 'rootfs.cpio.gz', 'wb') as archive:
                p.write_entry(archive, device)
                trailer = p.Entry('TRAILER!!!', {**fields, 'mode': 0}, b'')
                p.write_entry(archive, trailer)
            (root / 'bzImage').write_bytes(b'kernel-unchanged')
            overlay = root / 'payload'
            (overlay / 'etc/init.d').mkdir(parents=True)
            (overlay / 'etc/init.d/S80test').write_text('#!/bin/sh\necho ready\n')
            (root / 'permissions.txt').write_text('/etc/init.d/S80test f 755 0 0 - - - - -\n')
            args = p.build_parser().parse_args(['--bzimage',str(root/'bzImage'),'--rootfs',str(root/'rootfs.cpio.gz'),'--payload-dir',str(overlay),'--archive-dest','/','--permissions-file',str(root/'permissions.txt'),'--output-dir',str(root/'out'),'--output-bzimage-name','test.bzImage','--output-rootfs-name','test.rootfs.cpio.gz'])
            p.package_rootfs(args)
            entries = {e.name: e for e in p.parse_newc(gzip.decompress((root/'out/test.rootfs.cpio.gz').read_bytes()))}
            self.assertEqual(entries['dev/console'].fields['rdevmajor'], 5)
            self.assertEqual(stat.S_IFMT(entries['dev/console'].fields['mode']), stat.S_IFCHR)
            self.assertEqual(entries['etc/init.d/S80test'].fields['mode'] & 0o777, 0o755)
            self.assertEqual((root/'out/test.bzImage').read_bytes(), b'kernel-unchanged')
if __name__ == '__main__': unittest.main()
