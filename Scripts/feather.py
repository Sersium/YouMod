"""Publish immutable build records to Feather (stdlib only)."""
import base64
import copy
import json
import os
import plistlib
import zipfile
from pathlib import Path
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def update_manifest(data, entry):
    template = copy.deepcopy(data['apps'][0])
    versions = {v['version']: v for app in data['apps'] for v in app.get('versions', [])}
    versions[entry['version']] = entry
    # Numeric ordering also keeps a slow older build from becoming "latest".
    ordered = sorted(versions.values(), key=lambda v: tuple(int(n) for n in v['version'].split('-')[-1].split('.')), reverse=True)
    apps = []
    for index, version in enumerate(ordered):
        app = copy.deepcopy(template)
        app.update(name='YouTube (YouMod ' + version['version'].split('-')[-1] + ')' + (' · Latest' if index == 0 else ''),
                   version=version['version'], versionDate=version['date'],
                   versionDescription=version['localizedDescription'],
                   localizedDescription=version['localizedDescription'],
                   downloadURL=version['downloadURL'], size=version['size'],
                   versions=ordered if index == 0 else [version])
        # Keep the real IPA bundle ID. Feather lists each app object separately.
        apps.append(app)
    data['apps'] = apps
    data['news'] = [dict(identifier='youmod-' + v['version'],
                         title='YouMod ' + v['version'].split('-')[-1],
                         caption=v['localizedDescription'], date=v['date'],
                         url=v['downloadURL'].rsplit('/download/', 1)[0] + '/tag/' + v['downloadURL'].split('/download/')[1].split('/')[0],
                         notify=True) for v in ordered]
    return data


def api(path, method='GET', body=None):
    request = Request('https://api.github.com/repos/' + os.environ['GITHUB_REPOSITORY'] + '/' + path,
                      data=json.dumps(body).encode() if body is not None else None, method=method,
                      headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                               'Accept': 'application/vnd.github+json', 'Content-Type': 'application/json'})
    with urlopen(request, timeout=30) as response:
        return json.load(response)


def publish(record):
    for attempt in range(8):
        current = api('contents/feather.json?ref=main')
        data = json.loads(base64.b64decode(current['content']))
        content = json.dumps(update_manifest(data, record), indent=2) + '\n'
        try:
            api('contents/feather.json', 'PUT', {
                'message': 'Publish YouMod ' + record['version'] + ' to Feather [skip ci]',
                'branch': 'main', 'sha': current['sha'],
                'content': base64.b64encode(content.encode()).decode()})
            Path('feather.json').write_text(content)
            return
        except HTTPError as error:
            if error.code != 409 or attempt == 7:
                raise
            time.sleep(attempt + 1)
    raise RuntimeError('Feather publication did not complete')


def release_notes(version, sha, youtube_version):
    repo = os.environ['GITHUB_REPOSITORY']
    # Only ancestor release tags: concurrent newer builds must not change the diff base.
    previous = subprocess.run(['git', 'describe', '--tags', '--abbrev=0', '--match', 'v*', sha + '^'],
                              capture_output=True, text=True)
    fork_base = '9fd5117f780f6a0b9cf08cec29c47d5106781a7d'
    base = previous.stdout.strip() if previous.returncode == 0 else fork_base
    if subprocess.run(['git', 'merge-base', '--is-ancestor', fork_base, base], capture_output=True).returncode:
        base = fork_base
    revision = (base + '..' if base else '') + sha
    commits = subprocess.check_output(['git', 'log', '--no-merges', '--format=- %s (%h)', revision], text=True)
    commits = '\n'.join(line for line in commits.splitlines() if '[skip ci]' not in line)
    comparison = f'https://github.com/{repo}/compare/{base}...{sha}' if base else f'https://github.com/{repo}/commit/{sha}'
    notes = f'YouMod {version} · YouTube {youtube_version}\n\n{commits or "Rebuild of the same source."}\n\nFull diff: {comparison}\nSource: {sha}\n'
    return notes


def release_record(version, ipa, sha):
    repo = os.environ['GITHUB_REPOSITORY']
    tag = 'v' + version
    with zipfile.ZipFile(ipa) as archive:
        plist = next(name for name in archive.namelist() if name.startswith('Payload/') and name.endswith('.app/Info.plist') and name.count('/') == 2)
        youtube_version = plistlib.loads(archive.read(plist))['CFBundleShortVersionString']
    notes = release_notes(version, sha, youtube_version)
    date = subprocess.check_output(['git', 'show', '-s', '--format=%cI', sha], text=True).strip()
    record = dict(version=youtube_version + '-' + version, date=date, downloadURL=f'https://github.com/{repo}/releases/download/{tag}/YouTube_YouMod.ipa',
                  size=Path(ipa).stat().st_size, localizedDescription=notes)
    Path('release-notes.md').write_text(notes)
    Path('release-record.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


if __name__ == '__main__':
    if sys.argv[1] == 'record':
        release_record(*sys.argv[2:])
    elif sys.argv[1] == 'publish':
        publish(json.loads(Path(sys.argv[2]).read_text()))
    else:
        raise SystemExit('Usage: feather.py record VERSION IPA SHA | publish RECORD')
