"""Run: python3 Tests/check_watch_bar.py (C compiler required)."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Files/WatchActionBar.x').read_text()
start = source.index('static CGRect YMWatchViewCountFrame(')
helper = source[start:source.index('\n}\n', start) + 3]
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
#define CGRectGetMinX(r) ((r).origin.x)
#define CGRectGetMaxX(r) ((r).origin.x+(r).size.width)
#define CGRectGetMidY(r) ((r).origin.y+(r).size.height/2)
#define MIN(a,b) ((a)<(b)?(a):(b))
#define MAX(a,b) ((a)>(b)?(a):(b))
'''
cases = '''
int main(void) {
    // Screenshot: membership and subscription before the like control.
    CGRect a=YMWatchViewCountFrame(CGRectMake(114,0,56,44),CGRectMake(52,0,56,44),CGRectMake(192,0,40,44),1);
    assert(a.origin.x==100 && a.size.width==88 && CGRectGetMaxX(a)<192);
    // Channel without a Join button, including a narrower screen.
    CGRect b=YMWatchViewCountFrame(CGRectMake(44,0,96,44),CGRectZero,CGRectMake(150,0,40,44),1);
    assert(b.size.width>=44 && b.origin.x>=88 && CGRectGetMaxX(b)<150);
    // Missing native subscription target: preserve its existing hit target.
    CGRect c=YMWatchViewCountFrame(CGRectMake(114,0,56,44),CGRectMake(52,0,56,44),CGRectMake(192,0,40,44),0);
    assert(c.origin.x==52 && CGRectGetMaxX(c)<=114);
}
'''
with tempfile.TemporaryDirectory() as tmp:
    c = Path(tmp) / 'watch.c'; binary = Path(tmp) / 'watch'
    c.write_text(stubs + helper + cases)
    subprocess.run(['cc', '-Wall', '-Werror', str(c), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
assert 'addYogaChild:' not in source and 'addSubnode:' not in source
assert 'addTarget:target action:@selector(handleTap)' in source
assert 'id.sponsorship.sponsor.button' in source
print('PASS: view-count placement, subscription hit target, native actions and no Yoga mutation')
