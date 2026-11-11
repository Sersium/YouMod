"""Run source-backed UI logic checks; macOS also executes the Objective-C hooks."""
from pathlib import Path
import platform
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
tabs = (root / 'Files/Tabbar.x').read_text()
watch = (root / 'Files/WatchActionBar.x').read_text()
appearance = (root / 'Files/Apperence.x').read_text()


def function(source, signature):
    start = source.index(signature)
    return source[start:source.index('\n}\n', start) + 3]


surface = function(appearance, 'static BOOL YMSettingsIsLightSurface(')
with tempfile.TemporaryDirectory() as tmp:
    c = Path(tmp) / 'surface.c'
    binary = Path(tmp) / 'surface'
    c.write_text('#include <assert.h>\ntypedef double CGFloat; typedef int BOOL;\n' + surface + '''
int main(void) {
    assert(YMSettingsIsLightSurface(1,1,1,1));
    assert(YMSettingsIsLightSurface(.95,.95,.95,1));
    assert(!YMSettingsIsLightSurface(0,0,0,1));
    assert(!YMSettingsIsLightSurface(1,0,0,1));
    assert(!YMSettingsIsLightSurface(1,1,1,.1));
}
''')
    subprocess.run(['cc', '-Wall', '-Werror', str(c), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: OLED surface selection preserves dark, colored and transparent backgrounds')
keyboard = appearance.split('%group OLEDKeyboard', 1)[1]
assert 'CABackdropLayer' not in keyboard and 'me.window.layer' not in keyboard, 'Never hide key-rendering layers across the keyboard window'
assert 'isDarkMode(self) ? UIColor.blackColor : UIColor.clearColor' in keyboard
print('PASS: OLED keyboard preserves native key layers and light-mode background')

if platform.system() != 'Darwin':
    print('SKIP: Foundation runtime checks require macOS; the release workflow runs them')
    raise SystemExit(0)

mappings = tabs[tabs.index('static NSString *ymPivotIDForTabID'):tabs.index('@interface YTIPivotBarRenderer (YouModTabItems)')]
getters = tabs.split('%hook YTIPivotBarRenderer\n', 1)[1].split('%end', 1)[0]
getters = getters.replace('%orig', 'self.rawItems').replace('[[NSUserDefaults standardUserDefaults] arrayForKey:TabOrder]', '[preferences arrayForKey:TabOrder]')
for cls in ('YTIBrowseRequest', 'YTIPivotBarRenderer'):
    mappings = mappings.replace('%c(' + cls + ')', cls)
    getters = getters.replace('%c(' + cls + ')', cls)
browse = dict(browseIDForWhatToWatch='FEwhat_to_watch', browseIDForSubscriptionsTab='FEsubscriptions',
              browseIDForLibraryTab='FElibrary', browseIDForHistory='FEhistory',
              browseIDForGamingDestination='FEgaming', browseIDForSportsDestination='FEsports',
              browseIDForNotificationsInbox='FEnotifications_inbox', browseIDForMyVideos='FEmy_videos',
              browseIDForLearningDestination='FElearning')
browse_declarations = '\n'.join('+ (NSString *)' + name + ';' for name in browse)
browse_methods = '\n'.join('+ (NSString *)' + name + ' { return @"' + value + '"; }' for name, value in browse.items())
types = watch[watch.index('typedef struct'):watch.index('@interface ASLayoutElementStyleYoga')]
style = watch[watch.index('@interface ASLayoutElementStyleYoga'):watch.index('static ASDisplayNode *YMFindWatchNode')]
style = style.replace('@interface ASLayoutElementStyleYoga (YouModWatchRow)', '@interface ASLayoutElementStyleYoga : NSObject\n@property CGFloat flexGrow;')
node_helpers = function(watch, 'static ASDisplayNode *YMFindWatchNode(') + function(watch, 'static BOOL YMConfigureWatchRow(')
stubs = (root / 'Tests/fixtures/ui_compat.m').read_text()
program = stubs.replace('/* BROWSE_DECLARATIONS */', browse_declarations).replace('/* BROWSE_METHODS */', browse_methods)
program = program.replace('/* MAPPINGS */', mappings).replace('/* GETTERS */', getters)
program = program.replace('/* NODE_TYPES */', types + style).replace('/* NODE_HELPERS */', node_helpers)
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp) / 'compat.m'
    binary = Path(tmp) / 'compat'
    source.write_text(program)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: actual tab getter/count, preference changes, restored native items, live row styling and remeasurement guards')
