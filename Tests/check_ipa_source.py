"""Run: python3 Tests/check_ipa_source.py"""
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import zipfile
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
from ipa_source import source, inspect

config = {'url': 'https://example.com/old.ipa', 'sha256': 'a' * 64}
a = source(config)
b = source(config, 'https://example.com/new.ipa')
assert a['cache_key'] != b['cache_key'] and b['sha256'] == ''
assert source(config, refresh='42')['cache_key'] != a['cache_key']
for invalid in ('http://example.com/a.ipa', 'https://user:pass@example.com/a.ipa', 'https://example.com/a\nipa'):
    try: source({'url': invalid})
    except ValueError: pass
    else: raise AssertionError(invalid)
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'base.ipa'
    def build(encrypted=0, identifier='com.google.ios.youtube'):
        header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        binary = header + struct.pack('<6I', 0x2c, 24, 0, 0, encrypted, 0)
        with zipfile.ZipFile(path, 'w') as ipa:
            ipa.writestr('Payload/NewYouTube.app/Info.plist', plistlib.dumps(dict(CFBundleIdentifier=identifier,
                          CFBundleExecutable='NewYouTube', CFBundleShortVersionString='22.5.1')))
            ipa.writestr('Payload/NewYouTube.app/NewYouTube', binary)
    build()
    assert inspect(path) == '22.5.1', 'Use actual IPA version and executable name'
    for encrypted, identifier in ((1, 'com.google.ios.youtube'), (0, 'example.other')):
        build(encrypted, identifier)
        try: inspect(path)
        except ValueError: pass
        else: raise AssertionError('Invalid base accepted')
print('PASS: source override, cache invalidation, version detection, encrypted/wrong-app rejection')
