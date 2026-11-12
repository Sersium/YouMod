"""Exercise production text replacement and watch bindings on the macOS builder."""
from pathlib import Path
import platform
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Files/DeArrow.x').read_text()
watch = (root / 'Files/WatchActionBar.x').read_text()


def function(signature, file_source=source):
    start = re.search(re.escape(signature) + r'[^;{}]*\{', file_source).start()
    return file_source[start:file_source.index('\n}\n', start) + 3]


def hook(name):
    return source.split('%hook ' + name + '\n', 1)[1].split('%end', 1)[0].replace('%new', '')


assert 'mod.mutableString setString:' not in source
assert 'exclusionPaths' not in source, 'Button spacing must not alter title/channel glyph flow'
assert 'YMDeArrowBesideMenu' not in source
assert 'void YouModUpdateWatchTitlesForRow(' in source and 'YouModUpdateWatchTitlesForRow(bar)' in watch
assert 'templateURI' not in function('static void YouModApplyWatchTitles(') and 'isVisible' not in source, 'Collapsed watch titles must not depend on template ownership or flattened-node visibility'
assert 'setOnNodeDidLoad:' not in source and 'setOnNodeDidLayout:' not in source, 'Do not install callbacks before the native text controller exists'
assert 'ASDisplayNode *node = %orig;' in hook('ELMComponent') and 'YouModUpdateDescriptionTitle(node)' in hook('ELMComponent')
assert '%hook YTEngagementPanelView' not in source, 'Expanded titles must bind the native header component, independent of its panel host'
assert 'candidate != cell && CGRectGetMaxY(candidate.frame) <= CGRectGetMinY(actions)' in source
assert 'YouModBoundWatchTitle(self, attributedString)' in hook('ASTextNode')
assert '- (void)didLoad' not in hook('ASTextNode'), 'Do not subscribe every player/comment text node to branding updates'
assert 'addObserver:title selector:@selector(youmod_onDeArrowTextNotification:)' in source
native = (root / 'Files/ReturnYouTubeDislike.x').read_text().split('NSString *YouModCurrentWatchTitle(void)', 1)[1].split('\n}', 1)[0]
assert 'details.videoId isEqualToString:YouModCurrentWatchVideoID()' in native

if platform.system() != 'Darwin':
    print('SKIP: DeArrow attributed-text and watch-binding runtime checks require macOS')
    raise SystemExit(0)

program = (root / 'Tests/fixtures/dearrow_titles.m').read_text()
program = program.replace('/* TEXT_HELPERS */', ''.join(function(s) for s in (
    'static NSAttributedString *YouModDeArrowTitleText(', 'static NSString *YouModCleanDeArrowTitle(',
    'static BOOL YouModIsGroupedUploadText(', 'static BOOL YouModIsLikelyBadgeOrMetadata(')))
program = program.replace('/* WATCH_BINDING */', ''.join(function(s) for s in (
    'void YouModDeArrowBeginWatchVideo(', 'static NSAttributedString *YouModOriginalTitleText(',
    'static NSAttributedString *YouModReadTitleText(', 'static NSAttributedString *YouModWatchTitleValue(',
    'static BOOL YouModWatchTitleMatches(', 'static void YouModClearWatchTitle(', 'static NSAttributedString *YouModBoundWatchTitle(',
    'static void YouModUpdateWatchTitleLabel(', 'static void YouModUpdateWatchTitle(')))
collectors = function('static void YouModCollectCardNodes(') + function('static void YouModCollectNodesFromView(')
for name in ('ASTextNode', 'ASNetworkImageNode'):
    collectors = collectors.replace('%c(' + name + ')', name + '.class')
program = program.replace('/* NODE_COLLECTORS */', collectors)
scanner = ''.join(function(s) for s in ('static void YouModCollectWatchLabels(', 'static void YouModApplyWatchTitles(', 'void YouModUpdateWatchTitlesForRow('))
for name in ('YTPlayerView', 'YTMainAppPlayerOverlayView', '_ASCollectionViewCell'):
    scanner = scanner.replace('%c(' + name + ')', name + '.class')
program = program.replace('/* SCANNER_HELPERS */', scanner)
description = function('static void YouModCollectDescriptionLabels(') + function('static void YouModUpdateDescriptionTitle(') + function('static void YouModObserveDescriptionComponent(')
program = program.replace('/* DESCRIPTION_HELPERS */', description.replace('%c(ASTextNode)', 'ASTextNode.class'))
program = program.replace('/* DESCRIPTION_NODE_HOOKS */', hook('ASDisplayNode').replace('%orig;', ''))
component_hooks = hook('ELMComponent').replace('id component = %orig;', 'self = [super init]; self.templateURI = context; self.pendingNode = element; id component = self;')
program = program.replace('/* DESCRIPTION_COMPONENT_HOOKS */', component_hooks.replace('ASDisplayNode *node = %orig;', 'ASDisplayNode *node = [self materializeNativeNode];'))
program = program.replace('/* BUTTON_HIT_AREA */', function('- (BOOL)pointInside:'))
program = program.replace('/* CELL_HIT_TEST */', hook('_ASCollectionViewCell').replace('%orig', 'self.nativeHitView'))
program = program.replace('/* COLLECTION_HOOK */', hook('UICollectionView').replace('%orig;', ''))
program = program.replace('/* FEED_IDENTIFIERS */', function('BOOL YouModIsOverflowButtonIdentifier(') + function('BOOL YouModIsOverflowButtonView('))
ryd_source = (root / 'Files/ReturnYouTubeDislike.x').read_text()
program = program.replace('/* FEED_QUEUES */', function('static void YouModUpdateFeedDeArrow(') + function('static void YMUpdateFeedVotes(', ryd_source))
program = program.replace('/* FEED_LAYOUT */', function('- (void)layoutSubviews', hook('_ASDisplayView')).replace('%orig;', ''))
program = program.replace('/* FEED_CELL_LAYOUT */', hook('UICollectionViewCell').replace('%orig;', ''))
program = program.replace('/* WATCH_ROW_NOTIFICATION */', function('- (void)youmod_refreshWatchBar:', watch))
program = program.replace('/* LEGACY_HOOKS */', hook('YTSlimVideoInformationCell').replace('%orig;', ''))
labels = hook('UILabel')
attributed = function('- (void)setAttributedText:', labels).replace('%orig(value);', 'self.rawAttributedText = value; self.rawText = nil;').replace('%orig;', 'self.rawAttributedText = text; self.rawText = nil;')
plain = function('- (void)setText:', labels).replace('%orig;', 'self.rawText = text; self.rawAttributedText = nil;')
program = program.replace('/* LABEL_HOOKS */', attributed + plain + function('- (void)didMoveToWindow', labels).replace('%orig;', ''))
ryd = (root / 'Files/ReturnYouTubeDislike.x').read_text()
playback = function('static void YouModWatchVideoChanged(', ryd).replace('%c(YTInlineMutedPlaybackPlayerOverlayViewController)', 'YTInlineMutedPlaybackPlayerOverlayViewController.class')
program = program.replace('/* WATCH_PLAYBACK */', playback)
setter = function('- (void)setAttributedText:', hook('ASTextNode'))
for argument in ('watchText', 'attributedString', 'mod'):
    setter = setter.replace('%orig(' + argument + ')', 'self.rawAttributedText = ' + argument)
setter = setter.replace('%orig', 'self.rawAttributedText = attributedString').replace('%c(ASNetworkImageNode)', 'ASNetworkImageNode.class')
program = program.replace('/* FEED_TEXT_HOOK */', setter + function('- (void)didExitHierarchy', hook('ASTextNode')).replace('%orig;', ''))
with tempfile.TemporaryDirectory() as tmp:
    src, binary = Path(tmp) / 'titles.m', Path(tmp) / 'titles'
    src.write_text(program)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-framework', 'CoreGraphics', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=20)
print('PASS: watch and expanded titles, preserved selection, late branding, lazy native description nodes, mixed Yoga/native/expandable text, rendering-lock deferral, feed update coalescing and detach, body isolation, feed/notification touch routing, recycling and 10000 unrelated text updates')
