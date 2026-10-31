"""Run: python3 Tests/check_watch_bar.py (C compiler required)."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Files/WatchActionBar.x').read_text()
start = source.index('static CGRect YMWatchJoinViewsFrame(')
helper = source[start:source.index('\n}\n', start) + 3]
for name, file in [('YMWatchPrefixFrame', source), ('YMWatchReservedViewsFrame', source), ('YMVoteLabelFrame', (root / 'Files/ReturnYouTubeDislike.x').read_text())]:
    start = file.index('static CGRect ' + name + '(')
    helper += file[start:file.index('\n}\n', start) + 3]
stubs = '''
#include <assert.h>
typedef double CGFloat;
typedef int BOOL;
typedef struct { double x,y; } CGPoint;
typedef struct { double width,height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
#define CGRectMake(x,y,w,h) ((CGRect){{x,y},{w,h}})
#define CGRectZero CGRectMake(0,0,0,0)
#define CGRectIsEmpty(r) ((r).size.width<=0 || (r).size.height<=0)
#define CGRectGetMinY(r) ((r).origin.y)
#define CGRectGetMaxY(r) ((r).origin.y+(r).size.height)
#define CGRectGetMidX(r) ((r).origin.x+(r).size.width/2)
#define CGRectGetMinX(r) ((r).origin.x)
#define CGRectGetMaxX(r) ((r).origin.x+(r).size.width)
#define CGRectGetMidY(r) ((r).origin.y+(r).size.height/2)
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
'''
cases = '''
int main(void) {
    // A wide native slot must not center the count far away from Subscribe.
    CGRect a=YMWatchJoinViewsFrame(CGRectMake(100,0,150,44));
    assert(a.origin.x==100 && a.size.width==52);
    CGRect b=YMWatchReservedViewsFrame(CGRectMake(156,0,40,44),0);
    assert(b.origin.x==100 && b.size.width==52 && CGRectGetMaxX(b)+4==156);
    // If Like starts a second line, its reserved counter slot moves with it.
    CGRect wrapped=YMWatchReservedViewsFrame(CGRectMake(68,56,40,44),0);
    assert(wrapped.origin.x==12 && wrapped.origin.y==56 && CGRectGetMaxX(wrapped)+4==68);
    CGRect rtl=YMWatchReservedViewsFrame(CGRectMake(252,56,40,44),1);
    assert(rtl.origin.x==296 && rtl.origin.y==56 && rtl.size.width==52);
    // Tablet action row without Subscribe: a 52pt prefix and a 4pt gap.
    CGRect tabletLike=CGRectMake(12,0,107,32);
    CGRect prefix=YMWatchPrefixFrame(tabletLike);
    assert(prefix.size.width==52 && CGRectGetMaxX(prefix)+4==tabletLike.origin.x+56);
    // Shared tablet pill: labels must remain anchored to distinct icons.
    CGRect host=CGRectMake(0,0,107,32);
    CGRect like=YMVoteLabelFrame(CGRectMake(8,4,24,24),host);
    CGRect dislike=YMVoteLabelFrame(CGRectMake(79,4,24,24),host);
    assert(CGRectGetMaxX(like)<dislike.origin.x);
    assert(CGRectGetMidX(like)==20 && CGRectGetMidX(dislike)==91);
    // A wrapped shared host must keep each vote label on its icon's line.
    CGRect tallHost=CGRectMake(0,0,360,100);
    CGRect topVote=YMVoteLabelFrame(CGRectMake(8,4,24,24),tallHost);
    CGRect bottomVote=YMVoteLabelFrame(CGRectMake(8,60,24,24),tallHost);
    assert(topVote.origin.y==28 && CGRectGetMaxY(topVote)<56);
    assert(bottomVote.origin.y==84 && CGRectGetMaxY(bottomVote)<=100);
    // Legacy bars can use only the hidden Join slot; never cover Subscribe.
    CGRect c=YMWatchJoinViewsFrame(CGRectMake(52,0,56,44));
    assert(c.origin.x==52 && CGRectGetMaxX(c)<=114);
    assert(YMWatchJoinViewsFrame(CGRectZero).size.width==0);
}
'''
with tempfile.TemporaryDirectory() as tmp:
    c = Path(tmp) / 'watch.c'; binary = Path(tmp) / 'watch'
    c.write_text(stubs + helper + cases)
    subprocess.run(['cc', '-Wall', '-Werror', str(c), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
assert 'addYogaChild:' not in source and 'addSubnode:' not in source
assert 'YMCompactSubscribe' not in source and 'YMGeminiOverflow' not in source, 'Keep original Subscribe, Gemini and More hit targets'
assert 'id.sponsorship.sponsor.button' in source
assert 'YMWatchRowForControl(self)' in source
assert 'if (!like || !subscribe)' not in source, 'Tablet actions do not contain Subscribe'
assert 'frame = YMPrependWatchViews(bar, like)' in source
configure = source.split('static BOOL YMConfigureWatchRow(', 1)[1].split('static UIView *YMFindWatchControl', 1)[0]
assert 'layout.style.flexWrap = 1;' in configure
assert 'wrapper.style.height = automatic;' in configure and 'wrapper.style.maxHeight = automatic;' in configure
assert 'margin.start = (YMWatchDimension){1, 56}' in configure, 'The counter needs measured space when actions wrap'
assert 'child.style.flexGrow = 0' in configure, 'Do not stretch the gap after Subscribe'
layout = source.split('%hook _ASDisplayView', 1)[1]
assert '.style.' not in layout, 'Do not change native measurement from UIKit layout callbacks'
assert 'parent.yogaChildren.count != 1' in configure, 'Do not collapse a Join ancestor shared with other buttons'
assert '__weak UIView *weakBar' in source and '__weak ASDisplayNode *weakNode' in source
assert 'if (YMConfigureWatchRow(currentNode, wrap)) [currentNode setNeedsLayout]' in source
assert 'currentNode != ((_ASDisplayView *)currentBar).keepalive_node' in source, 'Skip recycled rows before the deferred update'
print('PASS: tight counter placement, wrapped/RTL rows, tablet fallback, native actions and no added Yoga children')
