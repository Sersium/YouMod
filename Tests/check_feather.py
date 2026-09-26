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
entry = dict(version=f'21.38.2-{major}.0.0.10', date='2026-09-26T12:00:00Z', size=123,
             localizedDescription='Fix thumbnails\n\nFull diff: https://github.com/Sersium/YouMod/compare/v2.1.5...abc',
             downloadURL=f'https://github.com/Sersium/YouMod/releases/download/v{major}.0.0.10/YouTube_YouMod.ipa')
updated = feather.update_manifest(copy.deepcopy(original), entry)
assert updated['apps'][0]['version'] == entry['version']
assert updated['apps'][0]['localizedDescription'] == entry['localizedDescription']
assert all(app['bundleIdentifier'] == 'com.google.ios.youtube' for app in updated['apps'])
assert len({app['version'] for app in updated['apps']}) == len(updated['apps'])
assert all(len(app['versions']) == 1 for app in updated['apps'][1:])
assert feather.update_manifest(copy.deepcopy(updated), entry) == updated, 'Reruns must be idempotent'
older = dict(entry, version=f'21.38.2-{major}.0.0.9', downloadURL=entry['downloadURL'].replace('.10/', '.9/'))
merged = feather.update_manifest(copy.deepcopy(updated), older)
assert merged['apps'][0]['version'] == entry['version'], 'Late builds must not replace latest'
assert len(merged['apps']) == len(updated['apps']) + 1
assert merged['apps'][1]['downloadURL'] == older['downloadURL']
assert merged['news'][0]['url'].endswith(f'/tag/v{major}.0.0.10')
assert all(v in merged['apps'][0]['versions'] for v in original['apps'][0]['versions'])
print('PASS: separate releases, real bundle ID, changelogs, history, reruns and out-of-order builds')
