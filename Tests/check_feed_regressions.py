"""Run: python3 Tests/check_feed_regressions.py (C compiler required).

Execute the production placement helper against screenshot-derived card bounds.
Source checks also guard the known request/layout loops and frozen audio getter.
On-device Texture layout and playback still require the accompanying smoke test.
"""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
dearrow = (root / 'Files/DeArrow.x').read_text()
player = (root / 'Files/Player.x').read_text()
ryd = (root / 'Files/ReturnYouTubeDislike.x').read_text()
start = dearrow.index('static CGRect YouModDeArrowButtonFrame(')
end = dearrow.index('\n}\n', start) + 3
helper = dearrow[start:end]
stubs = r'''
#include <assert.h>
typedef double CGFloat;
typedef struct { double x, y; } CGPoint;
typedef struct { double width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
#define CGRectZero ((CGRect){{0,0},{0,0}})
#define CGRectMake(x,y,w,h) ((CGRect){{x,y},{w,h}})
#define CGRectInset(r,dx,dy) CGRectMake((r).origin.x+(dx),(r).origin.y+(dy),(r).size.width-2*(dx),(r).size.height-2*(dy))
#define CGRectGetMidX(r) ((r).origin.x + (r).size.width / 2)
#define CGRectGetMaxX(r) ((r).origin.x + (r).size.width)
#define CGRectGetMaxY(r) ((r).origin.y + (r).size.height)
static int CGRectContainsRect(CGRect b, CGRect r) {
    return r.origin.x >= b.origin.x && r.origin.y >= b.origin.y &&
           CGRectGetMaxX(r) <= CGRectGetMaxX(b) && CGRectGetMaxY(r) <= CGRectGetMaxY(b);
}
static int intersects(CGRect a, CGRect b) {
    return a.origin.x < CGRectGetMaxX(b) && b.origin.x < CGRectGetMaxX(a) &&
           a.origin.y < CGRectGetMaxY(b) && b.origin.y < CGRectGetMaxY(a);
}
'''
cases = r'''
int main(void) {
    // Bounds, overflow menu, thumbnail, title: home, channel, notifications,
    // narrow phone, landscape, and RTL notification layout.
    CGRect cases[][4] = {
        {{{0,0},{393,310}}, {{342,226},{44,24}}, {{0,0},{393,221}}, {{55,229},{283,64}}},
        {{{0,0},{393,98}}, {{363,0},{30,24}}, {{16,0},{156,88}}, {{188,0},{169,82}}},
        {{{0,0},{393,114}}, {{363,0},{30,24}}, {{251,0},{112,64}}, {{58,0},{181,94}}},
        {{{0,0},{320,98}}, {{290,0},{30,24}}, {{16,0},{128,72}}, {{155,0},{129,84}}},
        {{{0,0},{844,100}}, {{800,0},{44,24}}, {{16,0},{160,90}}, {{188,0},{606,90}}},
        {{{0,0},{393,114}}, {{0,0},{30,24}}, {{30,0},{112,64}}, {{150,0},{181,94}}},
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); i++) {
        CGRect frame = YouModDeArrowButtonFrame(cases[i][0], cases[i][1]);
        assert(frame.size.width == 26 && frame.size.height == 26);
        assert(CGRectContainsRect(cases[i][0], frame));
        for (int j = 1; j < 4; j++) assert(!intersects(frame, cases[i][j]));
        // The expanded 44pt hit target must not steal overflow menu taps.
        CGRect hit = CGRectMake(frame.origin.x-9, frame.origin.y-9,44,44);
        assert(!intersects(hit, cases[i][1]));
    }
    // A one-line tablet card has no space below its menu. The fallback must
    // remain visible and keep the entire hit target away from menu and metadata.
    CGRect shortCard = CGRectMake(0,0,400,260), menu = CGRectMake(348,226,44,24);
    CGRect fallback = YouModDeArrowButtonFrame(shortCard, menu);
    assert(fallback.size.width==26 && fallback.origin.y==9);
    assert(CGRectContainsRect(shortCard, CGRectInset(fallback,-9,-9)));
    assert(!intersects(CGRectInset(fallback,-9,-9),menu));
    assert(CGRectGetMaxY(fallback)<226);
    CGRect frame = YouModDeArrowButtonFrame(CGRectMake(0,0,30,24), CGRectMake(0,0,30,24));
    assert(frame.size.width == 0); // Clipped wrapper: caller must ascend to the card.
}
'''
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp) / 'layout.c'
    binary = Path(tmp) / 'layout'
    source.write_text(stubs + helper + cases)
    subprocess.run([os.environ.get('CC', 'cc'), '-Wall', '-Werror', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

layout = dearrow.split('%hook _ASDisplayView', 1)[1].split('%new', 1)[0]
assert 'setURL:' not in layout, 'Layout must not restart thumbnail downloads'
assert 'fetched"] boolValue' in dearrow and 'branding[@"fetched"] = @YES' in dearrow
assert 'lastRequest.timeIntervalSinceNow < 60' in dearrow
assert '%hook YTIThumbnailDetails_Thumbnail' not in dearrow, 'Preserve original thumbnail identity'
assert 'keepalive_node' in dearrow and 'node.subnodes' in dearrow, 'Include layer-backed home cards'
image_hook = dearrow.split('%hook ASNetworkImageNode', 1)[1].split('%end', 1)[0]
assert '@selector(view)' not in image_hook, 'Never force a view for a layer-backed image node'
assert 'titleView.frame =' not in dearrow, 'Do not fight native title layout'
assert '- (BOOL)inlinePlaybackUnmutedAtStart {' not in player, 'Leave audio getter live after taps'
assert 'setInlinePlaybackUnmutedAtStart:YES' in player and 'if (newVideo' in player
assert 'addYogaChild:' not in ryd and 'addSubnode:' not in ryd and 'setMinWidth:' not in ryd, 'Do not mutate native vote layout trees'
assert 'CATextLayer' in ryd and 'button.isNodeLoaded' in ryd
assert '%orig(url, reset)' in image_hook and 'setURL:[NSURL' not in dearrow
assert 'CGImageSourceCreateThumbnailAtIndex' in dearrow and 'removeFromSuperlayer' in dearrow
assert 'didEnterVisibleState' in image_hook and 'drawParametersForAsyncLayer:' in image_hook
assert 'isNodeLoaded' not in image_hook and 'node.layer' not in image_hook, 'Flattened image nodes may have no layer'
assert 'setImage:' not in image_hook and 'setValue:replacement forKey:@"image"' in image_hook
assert 'layoutDidFinish' not in image_hook, 'Do not create a render/layout invalidation loop'
assert 'style == 0' in player and 'audioControlUIStyle' in player
assert 'view.frame =' not in ryd and 'pf.size.width += diff' not in ryd
assert 'didActivateNewPlaybackWithContentVideo:' in ryd and 'currentWatchPlayer.contentVideoID' in ryd
assert '%hook ELMContainerNode' in ryd, 'Both action bars need counts, independent of collection ID'
print('PASS: six card layouts, clipping, hit targets, and feed/audio/count regression guards')

# Initial/default sections must go through the same filter as network sections.
ads = (root / 'Files/Ads.x').read_text()
assert 'sectionControllersForSectionRenderers:' not in ads, 'Do not desynchronize backing sections and grid controllers'
assert '@[@"_sectionRenderers", @"_defaultSectionRenderers"]' in ads
assert 'hideHoriShelf && ((YTIShelfRenderer *)sectionRenderer)' not in ads, 'Preserve native recommendation shelves'
assert 'kFilteredSectionKey' not in ads, 'A renderer can change after its first pass'
assert '%init(YouModFeedFilters)' in ads, 'Feed preferences also apply with ads enabled'
tabs = (root / 'Files/Tabbar.x').read_text()
settings = (root / 'Files/YouModSettings.x').read_text()
assert 'YTIPivotBarRenderer *renderer = original;' in tabs, 'Preserve native tab renderer identity'
assert '[original copy]' not in tabs
assert tabs.count('%orig(YMOrderedPivotRenderer(renderer))') == 1, 'Order tabs once, in the shared view renderer'
assert 'if (!button.superview ||' in dearrow, 'Retry cards whose thumbnails arrive after initial layout'
assert 'if (ordered.count)' in tabs, 'An invalid saved order must not blank navigation'
assert '[self loadPivotBarWithOffline:NO triggeredByNotification:YES]' in settings
assert 'performSelector:@selector(refreshPivotBarWithTriggedByNotification:)' not in settings

# Exercise the actual ICU-pattern text from the implementation, translating the
# Unicode-codepoint escape into Python's equivalent for this portable check.
import ast
import re
start = ryd.index('static NSRange YMFeedViewCountRange(')
pattern_literal = re.search(r'pattern = \[NSRegularExpression regularExpressionWithPattern:@("(?:[^"\\]|\\.)*")', ryd[start:]).group(1)
pattern = ast.literal_eval(pattern_literal).replace(r'\x{00A0}', '\u00a0')
for text, views in [
    ('Channel  ▷319K  1d ago', '▷319K'),
    ('Channel  ▷2.7M  4y ago', '▷2.7M'),
    ('738K views · 1 day ago', '738K views'),
    ('201,361 views  2d ago', '201,361 views'),
    ('42 vues · hier', '42 vues'),
    ('Channel \ufffc124 3h ago', '\ufffc124'),
]:
    match = re.search(pattern, text, re.I)
    assert match and match.group().rstrip() == views, (text, match)
    decorated = text[:match.end()] + ' · 👍 10 · 👎 2' + text[match.end():]
    assert decorated.index('👍') > decorated.index(views)
plain_literal = re.search(r'standalone = \[NSRegularExpression regularExpressionWithPattern:@("(?:[^"\\]|\\.)*")', ryd[start:]).group(1)
plain = ast.literal_eval(plain_literal).replace(r'\x{00A0}', '\u00a0')
for text in ['124', '319K', '2.7M', '201,361']:
    assert re.fullmatch(plain, text), text
for text in ['Channel name', '12:34', '7y ago', 'LIVE', '544K subscribers']:
    assert not re.search(pattern, text, re.I) and not re.fullmatch(plain, text), text
feed = ryd.split('#pragma mark - Feed metadata', 1)[1].split('#pragma mark - Protobuf Model Hooks', 1)[0]
assert 'YouModVideoCard(menu, texts, images, &videoID)' in feed
assert 'YouModGetCurrentVideoID' not in feed, 'Feed identity must come from the card'
assert 'YMFeedBaseText' in feed and 'YMSettingFeedVotes' in feed
assert 'cachedVotesForVideoID:videoID' in feed and 'fetchVotesForVideoID:videoID' in feed
print('PASS: cold-start filter path, reversible tabs, feed metadata patterns and recycled-card identity guards')

assert 'setSupportsGridSurfaceInlinePlayback:(BOOL)supported' in player
assert '%orig(supported || UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad)' in player

# Shared by DeArrow and feed votes: reject player/detached controls before
# traversing Texture nodes during fullscreen transitions.
card_lookup = dearrow.split('UIView *YouModVideoCard(', 1)[1].split('%hook _ASDisplayView', 1)[0]
assert card_lookup.index('if (!cell) return nil;') < card_lookup.index('YouModCollectNodesFromView(')
assert '[cell isKindOfClass:%c(YTPlayerView)]' in card_lookup
assert '[cell isKindOfClass:%c(YTMainAppPlayerOverlayView)]' in card_lookup
assert '[cell isKindOfClass:[UICollectionViewCell class]]' in card_lookup
assert 'if (card == cell) break;' in card_lookup

# Logos hook self is unsafe-unretained: deferred work must resolve a weak
# reference while alive, then hold it strongly for the callback's duration.
assert '__weak ASNetworkImageNode *weakNode = self;' in image_hook
assert 'ASNetworkImageNode *node = weakNode;' in image_hook
assert 'if (node) YouModRefreshThumbnailNode(node);' in image_hook
assert 'YouModRefreshThumbnailNode(self); });' not in image_hook
watch = (root / 'Files/WatchActionBar.x').read_text()
deferred_watch = watch.split('dispatch_async(dispatch_get_main_queue(), ^{', 1)[1].split('});', 1)[0]
assert 'UIView *control = weakControl;' in deferred_watch
assert 'if (!control.window) return;' in deferred_watch
assert 'YMWatchRowForControl(self)' not in deferred_watch
