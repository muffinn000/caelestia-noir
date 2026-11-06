import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

PROFILE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('noir_installer', PROFILE/'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class InstallTests(unittest.TestCase):
    def test_dry_run_does_not_create_destination(self):
        with tempfile.TemporaryDirectory(prefix='.install-test-',dir=PROFILE) as temporary:
            home=Path(temporary)/'home'
            with contextlib.redirect_stdout(io.StringIO()):
                installer.install(home,dry_run=True)
            self.assertFalse(home.exists())

    def test_install_and_restore_preserve_symlink_and_user_state(self):
        with tempfile.TemporaryDirectory(prefix='.install-test-',dir=PROFILE) as temporary:
            home=Path(temporary)/'home'
            foot=home/'.config/foot/foot.ini'
            foot.parent.mkdir(parents=True)
            original=home/'original-foot.ini'
            original.write_text('# original configuration\n')
            foot.symlink_to(original)
            tasks=home/'.local/state/purple-desktop/tasks.json'
            tasks.parent.mkdir(parents=True)
            tasks.write_text('["keep this task"]')
            timer=tasks.with_name('timer.json')
            timer.write_text('{"seconds":480,"running":false}')
            with contextlib.redirect_stdout(io.StringIO()):
                backup=installer.install(home)
            self.assertFalse(foot.is_symlink())
            self.assertIn('background=0e0e0e',foot.read_text())
            self.assertEqual(original.read_text(),'# original configuration\n')
            self.assertEqual(tasks.read_text(),'["keep this task"]')
            self.assertEqual(timer.read_text(),'{"seconds":480,"running":false}')
            wallpaper=home/'.local/state/caelestia/wallpaper/current'
            self.assertTrue(wallpaper.is_symlink())
            self.assertTrue(wallpaper.exists())
            self.assertTrue((home/'.local/bin/noir-panel').stat().st_mode & 0o111)
            with contextlib.redirect_stdout(io.StringIO()):
                installer.restore(home,backup)
            self.assertTrue(foot.is_symlink())
            self.assertEqual(foot.read_text(),'# original configuration\n')
            self.assertFalse((home/'.local/bin/noir-panel').exists())
            self.assertFalse(wallpaper.is_symlink())
            self.assertEqual(tasks.read_text(),'["keep this task"]')
            self.assertEqual(timer.read_text(),'{"seconds":480,"running":false}')

    def test_restore_rejects_path_outside_target_home(self):
        with tempfile.TemporaryDirectory(prefix='.install-test-',dir=PROFILE) as temporary:
            home=Path(temporary)/'home'
            backup=Path(temporary)/'backup'
            backup.mkdir()
            (backup/'manifest.json').write_text(json.dumps([{'path':'../outside','existed':False}]))
            with self.assertRaises(ValueError):installer.restore(home,backup)

if __name__=='__main__':unittest.main()
