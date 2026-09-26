"""Fail publication if the ZIP is damaged, YouMod is unlinked, or roothide leaked in."""
from pathlib import Path
import plistlib
import struct
import sys
import zipfile


def libraries(binary):
    if binary[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a thin 64-bit Mach-O binary')
    offset = 32
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, size = struct.unpack_from('<II', binary, offset)
        if size < 8 or offset + size > len(binary):
            raise ValueError('Invalid Mach-O load command')
        if command in (0xc, 0x80000018, 0x8000001f):
            name = struct.unpack_from('<I', binary, offset + 8)[0]
            yield binary[offset + name:offset + size].split(b'\0')[0].decode()
        offset += size


def metadata(ipa):
    plists = [name for name in ipa.namelist() if name.startswith('Payload/') and name.endswith('.app/Info.plist') and name.count('/') == 2]
    if len(plists) != 1:
        raise ValueError('Expected one main app in the IPA')
    return plists[0][:-len('Info.plist')], plistlib.loads(ipa.read(plists[0]))


def verify(path):
    with zipfile.ZipFile(path) as ipa:
        assert ipa.testzip() is None, 'Corrupted IPA'
        app, info = metadata(ipa)
        executable = list(libraries(ipa.read(app + info['CFBundleExecutable'])))
        assert any(name.endswith('/YouMod.dylib') for name in executable), 'YouMod is not loaded by YouTube'
        for name in ('YouMod.dylib', 'YTVideoOverlay.dylib', 'DontEatMyContent.dylib'):
            dependencies = list(libraries(ipa.read(app + 'Frameworks/' + name)))
            assert not any('.jbroot' in d or 'libroothide' in d or d.startswith('/var/jb/') for d in dependencies), dependencies
    print(f'PASS: IPA integrity, injected YouMod and no jailbreak-only dependency ({Path(path).stat().st_size} bytes)')


if __name__ == '__main__':
    verify(sys.argv[1])
