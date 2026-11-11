#import <Foundation/Foundation.h>
#include <assert.h>
#define ShortsActionIndex 0
#define ShortsAutoSpeedIndex 1
#define AutoSpeedIndex 2
#define GlobalSpeedLocked 3
static NSInteger preferences[4];
#define INTFORVAL(key) preferences[key]
#define IS_ENABLED(key) (preferences[key] != 0)
static int originalCalls, nextCalls, shortsSpeedCalls, normalSpeedCalls;
@interface UIGestureRecognizer : NSObject
@end
@implementation UIGestureRecognizer
@end
@interface UIPinchGestureRecognizer : UIGestureRecognizer
@end
@implementation UIPinchGestureRecognizer
@end
@interface Player : NSObject
@property double currentVideoTotalMediaTime;
@property double seekTime;
- (void)seekToTime:(double)time;
- (void)YouModSetShortsAutoSpeed;
- (void)YouModSetAutoSpeed;
@end
@implementation Player
- (void)seekToTime:(double)time { self.seekTime = time; }
- (void)YouModSetShortsAutoSpeed { shortsSpeedCalls++; }
- (void)YouModSetAutoSpeed { normalSpeedCalls++; }
@end
@compatibility_alias YTPlayerViewController Player;
@interface Controller : NSObject
@property(strong) Player *player;
@property(strong) id delegate;
@property(strong) UIGestureRecognizer *YouModTapGesture;
@property BOOL paused;
- (void)pause;
- (void)handleLoopBehavior;
- (void)playbackControllerDidActivateVideo:(id)video withPlayerResponse:(id)response;
- (void)playbackSequentialItemControllerDidRequestNextReel:(id)sender isAutoAdvance:(BOOL)automatic;
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)other;
@end
@implementation Controller
- (void)pause { self.paused = YES; }
- (void)playbackSequentialItemControllerDidRequestNextReel:(id)sender isAutoAdvance:(BOOL)automatic { assert(sender && automatic); nextCalls++; }
/* HOOKS */
@end
int main(void) { @autoreleasepool {
    Controller *controller = [Controller new];
    controller.player = [Player new];
    controller.player.currentVideoTotalMediaTime = 10;
    controller.delegate = [Controller new];
    [controller handleLoopBehavior];
    assert(originalCalls == 1 && !controller.paused);
    preferences[ShortsActionIndex] = 1;
    [controller handleLoopBehavior];
    assert(nextCalls == 1 && originalCalls == 1);
    controller.delegate = nil;
    [controller handleLoopBehavior];
    assert(originalCalls == 2); // Keep native behavior if the delegate changes.
    preferences[ShortsActionIndex] = 2;
    [controller handleLoopBehavior];
    assert(controller.paused && controller.player.seekTime == 9.95);
    preferences[ShortsAutoSpeedIndex] = 3;
    preferences[AutoSpeedIndex] = 2;
    [controller playbackControllerDidActivateVideo:nil withPlayerResponse:nil];
    assert(shortsSpeedCalls == 1 && normalSpeedCalls == 0);
    preferences[ShortsAutoSpeedIndex] = 0;
    [controller playbackControllerDidActivateVideo:nil withPlayerResponse:nil];
    assert(shortsSpeedCalls == 1 && normalSpeedCalls == 1);
    preferences[AutoSpeedIndex] = 0;
    [controller playbackControllerDidActivateVideo:nil withPlayerResponse:nil];
    assert(normalSpeedCalls == 1);
    preferences[GlobalSpeedLocked] = 1;
    [controller playbackControllerDidActivateVideo:nil withPlayerResponse:nil];
    assert(normalSpeedCalls == 2);
    controller.YouModTapGesture = [UIGestureRecognizer new];
    assert([controller gestureRecognizer:controller.YouModTapGesture shouldRequireFailureOfGestureRecognizer:[UIPinchGestureRecognizer new]]);
    assert(![controller gestureRecognizer:controller.YouModTapGesture shouldRequireFailureOfGestureRecognizer:[UIGestureRecognizer new]]);
} return 0; }
