"""Check the upstream playback fixes against production helpers and hook bodies."""
from pathlib import Path
import platform
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
player = (root / 'Files/Player.x').read_text()
shorts = (root / 'Files/Shorts.x').read_text()


def function(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]


geometry = function(player, 'static CGPoint YouModSpeedToastCenter(')
stubs = '''#include <assert.h>
typedef double CGFloat;
typedef struct { double x,y; } CGPoint;
typedef struct { double top,left,bottom,right; } UIEdgeInsets;
#define CGPointMake(x,y) ((CGPoint){x,y})
#define MAX(a,b) ((a)>(b)?(a):(b))
'''
with tempfile.TemporaryDirectory() as tmp:
    src, binary = Path(tmp) / 'toast.c', Path(tmp) / 'toast'
    src.write_text(stubs + geometry + '''
int main(void) {
    CGPoint phone = YouModSpeedToastCenter(402,44,(UIEdgeInsets){62,0,34,0});
    assert(phone.x==201 && phone.y-22>=62+8);
    CGPoint landscape = YouModSpeedToastCenter(874,44,(UIEdgeInsets){0,62,21,0});
    assert(landscape.x==468 && landscape.y==36);
    CGPoint tablet = YouModSpeedToastCenter(834,52,(UIEdgeInsets){24,0,20,0});
    assert(tablet.x==417 && tablet.y-26>=32);
}
''')
    subprocess.run(['cc', '-Wall', '-Werror', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

preview = player.split('- (void)setActiveSingleVideo:', 1)[1].split('%end', 1)[0]
assert 'setMuted:IS_ENABLED(AutoFeedMute)' in preview
assert 'setInlinePlaybackUnmutedAtStart:!IS_ENABLED(AutoFeedMute)' in preview
assert 'setAudioSoundOn:!IS_ENABLED(AutoFeedMute)' in preview
assert 'if (newVideo' in preview, 'Manual audio changes must remain usable'
assert '%hook YTColdConfig\n- (BOOL)isLandscapeEngagementPanelEnabled' in player
assert player.count('- (BOOL)isLandscapeEngagementPanelEnabled') == 1
print('PASS: notch-safe speed indicator, preview mute preference and fullscreen config gate')

if platform.system() != 'Darwin':
    print('SKIP: Shorts and gesture runtime checks require macOS')
    raise SystemExit(0)

container = shorts.split('%hook YTReelContainerViewController\n', 1)[1].split('%end', 1)[0]
container = container.replace('%orig;', 'originalCalls++;')
gesture = function(player, '- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:')
program = (root / 'Tests/fixtures/player_regressions.m').read_text()
program = program.replace('/* HOOKS */', container + gesture)
with tempfile.TemporaryDirectory() as tmp:
    src, binary = Path(tmp) / 'player.m', Path(tmp) / 'player'
    src.write_text(program)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: current Shorts lifecycle, speed precedence, repeat/next/pause and pinch priority')
