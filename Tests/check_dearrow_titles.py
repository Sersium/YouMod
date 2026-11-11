"""Exercise production text replacement and watch bindings on the macOS builder."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Files/DeArrow.x').read_text()


def function(signature, file_source=source):
    start = file_source.index(signature)
    return file_source[start:file_source.index('\n}\n', start) + 3]


assert 'mod.mutableString setString:' not in source
assert 'YMDeArrowOverThumbnail' not in source
assert 'YMDeArrowExclusionRect' in source, 'Exclusion paths must not trigger a layout loop'
assert '%hook YTSlimVideoInformationCellController' in source
assert 'self.videoID' in source and 'YMWatchTitleVideoID' in source
assert 'void YouModUpdateWatchDeArrowButton(' in source
assert 'YouModCurrentWatchVideoID()' in source
assert '%hook ELMTextNode' in source
assert 'visibleCells' not in source, 'Bind the rendered text leaf independently of collection wrappers'
assert 'video_metadata_inner.eml' in source and 'video_metadata.eml' in source
binding = function('static void YouModUpdateWatchTitleLabel(')
assert 'kYMDeArrowVideoIDKey' not in binding, 'Watch bindings must not activate global feed text observers'
native = (root / 'Files/ReturnYouTubeDislike.x').read_text().split('NSString *YouModCurrentWatchTitle(void)', 1)[1].split('\n}', 1)[0]
assert 'details.videoId isEqualToString:YouModCurrentWatchVideoID()' in native

if platform.system() != 'Darwin':
    print('SKIP: DeArrow attributed-text and watch-binding runtime checks require macOS')
    raise SystemExit(0)

program = (root / 'Tests/fixtures/dearrow_titles.m').read_text()
program = program.replace('/* TEXT_HELPERS */', function('static NSAttributedString *YouModDeArrowTitleText(') +
                          function('static NSString *YouModCleanDeArrowTitle(') +
                          function('static BOOL YouModIsGroupedUploadText(') + function('static BOOL YouModIsLikelyBadgeOrMetadata('))
program = program.replace('/* WATCH_BINDING */', function('void YouModDeArrowBeginWatchVideo(') + function('static NSAttributedString *YouModOriginalTitleText(') +
                          function('static void YouModUpdateWatchTitleLabel(') + function('static void YouModUpdateWatchTitle('))
program = program.replace('/* EXCLUSION_HELPER */', function('static void YouModReserveToggleText('))
elements = function('static BOOL YouModIsWatchMetadataNode(') + function('static void YouModUpdateElementsWatchTitle(')
program = program.replace('/* ELEMENTS_HELPERS */', elements)
hooks = source.split('%hook ELMTextNode\n', 1)[1].split('%end', 1)[0]
program = program.replace('/* ELEMENTS_HOOKS */', hooks.replace('%orig;', '').replace('%new', ''))
legacy_hooks = source.split('%hook YTSlimVideoInformationCell\n', 1)[1].split('%end', 1)[0]
program = program.replace('/* LEGACY_HOOKS */', legacy_hooks.replace('%orig;', '').replace('%new', ''))
ryd = (root / 'Files/ReturnYouTubeDislike.x').read_text()
playback = function('static void YouModWatchVideoChanged(', ryd).replace('%c(YTInlineMutedPlaybackPlayerOverlayViewController)', 'YTInlineMutedPlaybackPlayerOverlayViewController.class')
program = program.replace('/* WATCH_PLAYBACK */', playback)
text_hook = source.split('%hook ASTextNode\n', 1)[1].split('%end', 1)[0]
assert '- (void)didLoad' not in text_hook, 'Do not subscribe every player/comment text node to branding updates'
assert 'addObserver:title selector:@selector(youmod_onDeArrowTextNotification:)' in source
setter = function('- (void)setAttributedText:', text_hook)
setter = setter.replace('%orig(attributedString)', 'self.rawAttributedText = attributedString').replace('%orig(mod)', 'self.rawAttributedText = mod').replace('%orig', 'self.rawAttributedText = attributedString')
program = program.replace('/* FEED_TEXT_HOOK */', setter.replace('%c(ASNetworkImageNode)', 'ASNetworkImageNode.class'))
with tempfile.TemporaryDirectory() as tmp:
    src, binary = Path(tmp) / 'titles.m', Path(tmp) / 'titles'
    src.write_text(program)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-framework', 'CoreGraphics', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
print('PASS: production title bindings with simulated visible leaves, async native refresh, toggles, legacy cells, recycling and cyclic ownership')
