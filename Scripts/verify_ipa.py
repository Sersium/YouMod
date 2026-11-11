"""Fail publication if the ZIP is damaged, YouMod is unlinked, or roothide leaked in."""
from pathlib import Path
import plistlib
import struct
import sys
import zipfile


def libraries(binary):
    if len(binary) < 32 or binary[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a thin 64-bit Mach-O binary')
    count, command_bytes = struct.unpack_from('<II', binary, 16)
    end = 32 + command_bytes
    if end > len(binary):
        raise ValueError('Truncated Mach-O load commands')
    offset = 32
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError('Truncated Mach-O load command')
        command, size = struct.unpack_from('<II', binary, offset)
        if size < 8 or size % 8 or offset + size > end:
            raise ValueError('Invalid Mach-O load command')
        if command == 0x19:  # LC_SEGMENT_64: injection must not overwrite section data.
            if size < 72:
                raise ValueError('Invalid Mach-O segment')
            sections = struct.unpack_from('<I', binary, offset + 64)[0]
            if 72 + sections * 80 > size:
                raise ValueError('Invalid Mach-O section table')
            for index in range(sections):
                section = offset + 72 + index * 80
                length, data_offset = struct.unpack_from('<QI', binary, section + 40)
                section_type = struct.unpack_from('<I', binary, section + 64)[0] & 0xff
                if length and data_offset and section_type not in (1, 12, 18) and data_offset < end:
                    raise ValueError('Injected load commands overlap Mach-O section data')
        if command in (0xc, 0x80000018, 0x8000001f):
            if size < 24:
                raise ValueError('Invalid Mach-O library command')
            name = struct.unpack_from('<I', binary, offset + 8)[0]
            if name < 24 or name >= size or b'\0' not in binary[offset + name:offset + size]:
                raise ValueError('Invalid Mach-O library name')
            yield binary[offset + name:offset + size].split(b'\0')[0].decode()
        offset += size
    if offset != end:
        raise ValueError('Mach-O command count does not match its size')


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
