"""Run: python3 Tests/check_feather.py"""
import copy
import importlib.util
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('feather', root / 'Scripts/feather.py')
feather = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feather)
original = json.loads((root / 'feather.json').read_text())
# Use a higher test major regardless of the real source's newest build.
major = max(int(a['version'].split('-')[-1].split('.')[0]) for a in original['apps']) + 1
entry = dict(version=f'{major}.1', date='2026-09-26T12:00:00Z', size=123,
             localizedDescription='Fix thumbnails\n\nFull diff: https://github.com/Sersium/YouMod/compare/v2.1.5...abc',
             downloadURL=f'https://github.com/Sersium/YouMod/releases/download/v{major}.1/YouTube_YouMod.ipa')
updated = feather.update_manifest(copy.deepcopy(original), entry)
assert updated['apps'][0]['version'] == entry['version']
assert updated['apps'][0]['localizedDescription'] == entry['localizedDescription']
assert all(app['bundleIdentifier'] == 'com.google.ios.youtube' for app in updated['apps'])
assert len({app['version'] for app in updated['apps']}) == len(updated['apps'])
assert all(len(app['versions']) == 1 for app in updated['apps'][1:])
assert feather.update_manifest(copy.deepcopy(updated), entry) == updated, 'Reruns must be idempotent'
older = dict(entry, version=f'{major}.0', downloadURL=entry['downloadURL'].replace(f'v{major}.1/', f'v{major}.0/'))
merged = feather.update_manifest(copy.deepcopy(updated), older)
assert merged['apps'][0]['version'] == entry['version'], 'Late builds must not replace latest'
assert len(merged['apps']) == len(updated['apps']) + 1
assert merged['apps'][1]['downloadURL'] == older['downloadURL']
assert merged['news'][0]['url'].endswith(f'/tag/v{major}.1')
assert all(v in merged['apps'][0]['versions'] for v in original['apps'][0]['versions'])
print('PASS: separate releases, real bundle ID, changelogs, history, reruns and out-of-order builds')

assert [feather.build_version('2.3', n, 42) for n in range(42, 51)] == [
    '2.3', '2.4', '2.5', '2.6', '2.7', '2.8', '2.9', '3.0', '3.1']
assert feather.build_version('2.3', '42', '42') == '2.3'
assert feather.build_version('2.3', 119, 42) == '10.0'
for args in [('2.10', 42, 42), ('2.2.0', 42, 42), ('2.3', 41, 42)]:
    try:
        feather.build_version(*args)
    except ValueError:
        pass
    else:
        raise AssertionError(args)
legacy = dict(entry, version='21.38.2-2.2.0.41')
clean = dict(entry, version='2.3')
assert feather.update_manifest({'apps': [dict(original['apps'][0], versions=[legacy])]}, clean)['apps'][0]['version'] == '2.3'

# The actual record writer must use the clean version while retaining the base
# app version in release notes.
import os
import plistlib
import tempfile
import zipfile
from unittest.mock import patch
cwd = Path.cwd()
with tempfile.TemporaryDirectory() as tmp:
    try:
        os.chdir(tmp)
        with zipfile.ZipFile('base.ipa', 'w') as ipa:
            ipa.writestr('Payload/YouTube.app/Info.plist', plistlib.dumps({'CFBundleShortVersionString': '21.38.2'}))
        with patch.dict(os.environ, GITHUB_REPOSITORY='Sersium/YouMod'), \
             patch.object(feather, 'release_notes', return_value='YouMod 2.3 · YouTube 21.38.2') as notes, \
             patch.object(feather.subprocess, 'check_output', return_value='2026-09-27T12:00:00Z'):
            record = feather.release_record('2.3', 'base.ipa', 'abc')
            notes.assert_called_once_with('2.3', 'abc', '21.38.2')
            assert record['version'] == '2.3'
            assert '/v2.3/' in record['downloadURL']
            assert json.loads(Path('release-record.json').read_text()) == record
    finally:
        os.chdir(cwd)
print('PASS: clean release records, legacy history, decimal rollover and stable rerun versions')
