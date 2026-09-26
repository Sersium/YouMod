"""Resolve a saved/manual base IPA, then validate its identity and encryption state."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import sys
from urllib.parse import urlparse
import zipfile
from verify_ipa import metadata


def source(config, override_url='', override_sha='', refresh=''):
    url = override_url.strip() or config['url']
    checksum = (override_sha.strip() if override_url.strip() else override_sha.strip() or config.get('sha256', '')).lower()
    parsed = urlparse(url)
    if parsed.scheme != 'https' or not parsed.netloc or parsed.username or '\n' in url or '\r' in url:
        raise ValueError('The IPA source must be a direct HTTPS URL without embedded credentials')
    if checksum and not re.fullmatch(r'[a-f0-9]{64}', checksum):
        raise ValueError('SHA-256 must contain exactly 64 hexadecimal characters')
    key = hashlib.sha256((url + '\n' + checksum + '\n' + refresh).encode()).hexdigest()
    return dict(url=url, sha256=checksum, cache_key='youtube-ipa-' + key)


def arm64(binary):
    if binary[:4] == b'\xcf\xfa\xed\xfe':
        return binary
    magic = binary[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        count = struct.unpack_from('>I', binary, 4)[0]
        stride = 32 if magic[-1] == 0xbf else 20
        for index in range(count):
            offset = 8 + index * stride
            cpu = struct.unpack_from('>I', binary, offset)[0]
            start, size = struct.unpack_from('>QQ' if stride == 32 else '>II', binary, offset + 8)
            if cpu == 0x100000c:
                if start + size > len(binary):
                    raise ValueError('Invalid arm64 slice')
                return arm64(binary[start:start + size])
    raise ValueError('The IPA must contain an arm64 executable')


def inspect(path, checksum=''):
    if checksum:
        with open(path, 'rb') as file:
            digest = hashlib.file_digest(file, 'sha256').hexdigest()
        if digest != checksum:
            raise ValueError('IPA SHA-256 does not match')
    with zipfile.ZipFile(path) as ipa:
        if ipa.testzip() is not None:
            raise ValueError('Damaged IPA archive')
        app, info = metadata(ipa)
        if info.get('CFBundleIdentifier') != 'com.google.ios.youtube':
            raise ValueError('Expected a decrypted YouTube IPA')
        binary = arm64(ipa.read(app + info['CFBundleExecutable']))
        offset = 32
        for _ in range(struct.unpack_from('<I', binary, 16)[0]):
            command, size = struct.unpack_from('<II', binary, offset)
            if size < 8 or offset + size > len(binary):
                raise ValueError('Invalid executable load command')
            if command in (0x21, 0x2c) and struct.unpack_from('<I', binary, offset + 16)[0] != 0:
                raise ValueError('The IPA is still encrypted; provide a decrypted IPA')
            offset += size
        version = info.get('CFBundleShortVersionString', '')
        if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)*', version):
            raise ValueError('Missing or invalid YouTube version')
        return version


if __name__ == '__main__':
    if sys.argv[1] == 'resolve':
        result = source(json.loads(Path('ipa-source.json').read_text()), os.environ.get('IPA_URL', ''),
                        os.environ.get('IPA_SHA256', ''), os.environ.get('CACHE_REFRESH', ''))
    else:
        result = {'youtube_version': inspect(sys.argv[2], os.environ.get('IPA_SHA256', ''))}
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in result.items():
            output.write(f'{key}={value}\n')
