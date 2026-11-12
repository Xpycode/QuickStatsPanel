#!/usr/bin/env python3
"""Headless, disposable fixture checks; no signing keys, apps or disk images used."""
import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('validation', Path(__file__).with_name('verify-appcast-input.py'))
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class ReleaseInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='qsp-release-input-')
        self.root = Path(self.temp.name)
        self.app = self.root / 'export/QuickStatsPanel.app'
        self.enclosed = self.root / 'mount/QuickStatsPanel.app'
        self.dmg = self.root / 'QuickStatsPanel-1.2.1-1201.dmg'
        self.feed = 'https://apps.lucesumbrarum.com/quickstatspanel/appcast.xml'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/MacOS/QuickStatsPanel').write_bytes(b'fixture executable')
        (self.app / 'Contents/MacOS/current').symlink_to('QuickStatsPanel')
        self.plist = {
            'CFBundleIdentifier': 'com.sim.QuickStatsPanel',
            'CFBundleShortVersionString': '1.2.1', 'CFBundleVersion': '1201',
            'LSMinimumSystemVersion': '15.0', 'SUFeedURL': self.feed,
            'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
        }
        self.write_plist()
        shutil.copytree(self.app, self.enclosed, symlinks=True)

    def tearDown(self):
        self.temp.cleanup()

    def write_plist(self):
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(self.plist))

    def verify(self):
        validation.verify(self.app, self.enclosed, self.dmg, self.feed)

    def test_matching_app_passes(self):
        self.verify()

    def test_modified_payload_rejected(self):
        (self.enclosed / 'Contents/MacOS/QuickStatsPanel').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.verify()

    def test_materialized_symlink_rejected(self):
        path = self.enclosed / 'Contents/MacOS/current'
        path.unlink()
        path.write_bytes(b'fixture executable')
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.verify()

    def test_wrong_feed_and_disabled_verification_rejected(self):
        for key, value in [('SUFeedURL', 'https://example.invalid/appcast.xml'),
                           ('SURequireSignedFeed', False),
                           ('SUVerifyUpdateBeforeExtraction', False)]:
            with self.subTest(key=key):
                original = self.plist[key]
                self.plist[key] = value
                self.write_plist()
                with self.assertRaises(ValueError):
                    self.verify()
                self.plist[key] = original

    def test_version_name_mismatch_rejected(self):
        self.dmg = self.root / 'QuickStatsPanel-1.2.1-1200.dmg'
        with self.assertRaisesRegex(ValueError, 'filename'):
            self.verify()

    def test_debug_modes_or_extra_files_rejected(self):
        executable = self.enclosed / 'Contents/MacOS/QuickStatsPanel'
        executable.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.verify()
        executable.chmod(0o644)
        (self.enclosed / 'Contents/extra').write_text('not in source')
        with self.assertRaisesRegex(ValueError, 'differs'):
            self.verify()


if __name__ == '__main__':
    unittest.main()
