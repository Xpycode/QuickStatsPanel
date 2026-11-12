#!/usr/bin/env python3
"""Validate identity/config and compare every regular file/symlink in two apps."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import sys


def manifest(root):
    result = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(base) / name
            relative = str(path.relative_to(root))
            if path.is_symlink():
                result[relative] = ('symlink', os.readlink(path))
            elif path.is_file():
                result[relative] = ('file', path.stat().st_mode & 0o777,
                                    hashlib.sha256(path.read_bytes()).hexdigest())
            else:
                result[relative] = ('directory',)
    return result


def verify(app, enclosed, dmg, feed):
    p = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if p.get('CFBundleIdentifier') != 'com.sim.QuickStatsPanel':
        raise ValueError('Unexpected bundle identity')
    version, build = p.get('CFBundleShortVersionString', ''), p.get('CFBundleVersion', '')
    if not re.fullmatch(r'\d+(?:\.\d+)*', version) or not re.fullmatch(r'\d+', build):
        raise ValueError('Expected numeric version and build')
    if dmg.name != f'QuickStatsPanel-{version}-{build}.dmg':
        raise ValueError('DMG filename must include the actual version and build')
    if p.get('SUFeedURL') != feed:
        raise ValueError('App feed URL differs from the publication URL')
    if not p.get('SURequireSignedFeed') or not p.get('SUVerifyUpdateBeforeExtraction'):
        raise ValueError('Signed-feed and pre-extraction verification must be enabled')
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', p.get('LSMinimumSystemVersion', '')):
        raise ValueError('Missing or invalid minimum OS version')
    if manifest(app) != manifest(enclosed):
        raise ValueError('DMG enclosed app differs from the supplied exported app')


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(str(error))
