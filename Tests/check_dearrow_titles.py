"""Exercise production text replacement and watch bindings on the macOS builder."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Files/DeArrow.x').read_text()


def function(signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]


assert 'mod.mutableString setString:' not in source
assert 'YMDeArrowOverThumbnail' not in source
assert 'YMDeArrowExclusionRect' in source, 'Exclusion paths must not trigger a layout loop'
assert '%hook YTSlimVideoInformationCellController' in source
assert 'self.videoID' in source and 'YMWatchTitleVideoID' in source
assert 'YouModWatchRowForControl(self)' in source
assert 'YouModCurrentWatchVideoID()' in source

if platform.system() != 'Darwin':
    print('SKIP: DeArrow attributed-text and watch-binding runtime checks require macOS')
    raise SystemExit(0)

program = (root / 'Tests/fixtures/dearrow_titles.m').read_text()
program = program.replace('/* TEXT_HELPERS */', function('static NSAttributedString *YouModDeArrowTitleText(') +
                          function('static NSString *YouModCleanDeArrowTitle('))
program = program.replace('/* WATCH_BINDING */', function('static void YouModUpdateWatchTitle('))
program = program.replace('/* EXCLUSION_HELPER */', function('static void YouModReserveToggleText('))
with tempfile.TemporaryDirectory() as tmp:
    src, binary = Path(tmp) / 'titles.m', Path(tmp) / 'titles'
    src.write_text(program)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-framework', 'CoreGraphics', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: clean title glyphs, Unicode spacing, native styling, watch defaults, toggles and reused cells')
