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

layout = dearrow.split('- (void)layoutSubviews {', 1)[1].split('%new', 1)[0]
assert 'setURL:' not in layout, 'Layout must not restart thumbnail downloads'
assert 'fetched"] boolValue' in dearrow and 'branding[@"fetched"] = @YES' in dearrow
assert 'lastRequest.timeIntervalSinceNow < 60' in dearrow
assert '%hook YTIThumbnailDetails_Thumbnail' not in dearrow, 'Preserve original thumbnail identity'
assert 'keepalive_node' in dearrow and 'node.subnodes' in dearrow, 'Include layer-backed home cards'
assert 'titleView.frame =' not in dearrow, 'Do not fight native title layout'
assert '- (BOOL)inlinePlaybackUnmutedAtStart {' not in player, 'Leave audio getter live after taps'
assert 'setInlinePlaybackUnmutedAtStart:YES' in player and 'if (newVideo' in player
assert '[container addYogaChild:added]' in ryd and '[container.style setMinWidth:' in ryd
assert 'view.frame =' not in ryd and 'pf.size.width += diff' not in ryd
assert '%hook ELMContainerNode' in ryd, 'Both action bars need counts, independent of collection ID'
print('PASS: six card layouts, clipping, hit targets, and feed/audio/count regression guards')
