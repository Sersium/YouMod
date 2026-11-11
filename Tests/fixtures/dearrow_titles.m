#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#include <assert.h>
#define NSFontAttributeName @"NSFont"
#define NSForegroundColorAttributeName @"NSColor"
#define NSParagraphStyleAttributeName @"NSParagraphStyle"
#define DeArrowEnabled 0
#define DeArrowReplaceTitles 1
#define ReturnYouTubeDislike 2
static BOOL preferences[] = {YES, YES, NO};
#define IS_ENABLED(key) preferences[key]
static NSString * const kYMDeArrowUpdatedNotification = @"YouModDeArrowUpdatedNotification";
static NSString * const kYMReturnDislikeNotification = @"YouModReturnDislikeNotification";
static NSString *currentWatchID, *detailsID, *detailsTitle;
static NSString *YouModCurrentWatchVideoID(void);
static NSString *YouModCurrentWatchTitle(void);
/* TEXT_HELPERS */

@class ASDisplayNode;
@interface UIView : NSObject
@property BOOL window;
@property CGRect frame;
@property(readonly) CGRect bounds;
@property(weak) UIView *superview;
@property(copy) NSArray *subviews;
@property(strong) ASDisplayNode *keepalive_node;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@implementation UIView
- (CGRect)bounds { return CGRectMake(0,0,self.frame.size.width,self.frame.size.height); }
- (void)setSubviews:(NSArray *)views { _subviews = [views copy]; for (UIView *v in views) v.superview = self; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    for (UIView *p=self; p && p != view; p=p.superview) rect = CGRectOffset(rect,p.frame.origin.x,p.frame.origin.y);
    return rect;
}
@end
@interface UILabel : UIView
@property(copy) NSAttributedString *rawAttributedText;
@property(copy) NSString *rawText;
@property(copy) NSAttributedString *attributedText;
@property(copy) NSString *text;
@property(strong) id font;
@property(strong) id textColor;
@end
@interface ASDisplayNode : NSObject
@property BOOL isNodeLoaded;
@property BOOL layerBacked;
@property(strong) ASDisplayNode *supernode;
@property(strong) UIView *view;
@property CGRect bounds;
@property(copy) NSArray *subnodes;
@property(copy) NSArray *yogaChildren;
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node;
@end
@implementation ASDisplayNode
- (UIView *)view { assert(!self.layerBacked); return _view; }
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node { return rect; }
@end
@interface ASTextNode : ASDisplayNode
@property(copy) NSAttributedString *attributedText;
@end
@interface ASNetworkImageNode : ASDisplayNode
@end
@implementation ASNetworkImageNode
@end
@implementation ASTextNode
@end
@interface TestLabel : NSObject
@property(copy) NSAttributedString *attributedText;
@end
@implementation TestLabel
@end
@interface YTSlimVideoInformationCell : NSObject
@property BOOL window;
@property(strong) TestLabel *titleLabel;
@property(strong) id experimentalTitleLabel;
- (void)didMoveToWindow;
- (void)layoutSubviews;
- (void)prepareForReuse;
@end
static void YouModUpdateWatchTitle(YTSlimVideoInformationCell *cell);
@implementation YTSlimVideoInformationCell
/* LEGACY_HOOKS */
@end
@interface YouModDeArrowManager : NSObject
@property(strong) NSMutableDictionary *originals;
@property(strong) NSMutableDictionary *titles;
@property(strong) NSMutableSet *toggled;
@property NSUInteger titleQueries;
+ (instancetype)sharedInstance;
- (void)registerOriginalTitle:(NSString *)title forVideoID:(NSString *)videoID;
- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID;
- (NSString *)titleForVideoID:(NSString *)videoID;
- (NSString *)originalTitleForVideoID:(NSString *)videoID;
- (void)prefetchBrandingForVideoID:(NSString *)videoID;
- (BOOL)toggleDeArrowForVideoID:(NSString *)videoID;
@end
@implementation YouModDeArrowManager
+ (instancetype)sharedInstance {
    static YouModDeArrowManager *manager;
    if (!manager) {
        manager = [self new];
        manager.originals = [NSMutableDictionary new];
        manager.titles = [NSMutableDictionary new];
        manager.toggled = [NSMutableSet new];
    }
    return manager;
}
- (void)registerOriginalTitle:(NSString *)title forVideoID:(NSString *)videoID { if (!self.originals[videoID]) self.originals[videoID] = title; }
- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID { return [self.toggled containsObject:videoID]; }
- (NSString *)titleForVideoID:(NSString *)videoID { self.titleQueries++; return [self.toggled containsObject:videoID] ? self.originals[videoID] : self.titles[videoID]; }
- (NSString *)originalTitleForVideoID:(NSString *)videoID { return self.originals[videoID]; }
- (void)prefetchBrandingForVideoID:(NSString *)videoID {}
- (BOOL)toggleDeArrowForVideoID:(NSString *)videoID {
    if ([self.toggled containsObject:videoID]) [self.toggled removeObject:videoID];
    else [self.toggled addObject:videoID];
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":videoID}];
    return [self.toggled containsObject:videoID];
}
@end
/* NODE_COLLECTORS */
/* WATCH_BINDING */
@implementation UILabel
- (NSAttributedString *)attributedText { return self.rawAttributedText; }
- (NSString *)text { return self.rawText ?: self.rawAttributedText.string; }
/* LABEL_HOOKS */
@end
@interface FeedTextHook : ASTextNode
@property BOOL forbidParentAccess;
@property NSUInteger parentReads;
@property(copy) NSAttributedString *rawAttributedText;
@end
@implementation FeedTextHook
- (ASDisplayNode *)supernode { self.parentReads++; assert(!self.forbidParentAccess); return [super supernode]; }
- (NSAttributedString *)attributedText { return self.rawAttributedText; }
/* FEED_TEXT_HOOK */
@end

@interface YTPlayerViewController : NSObject
@property BOOL isInlinePlaybackActive;
@property(strong) id activeVideoPlayerOverlay;
@property(copy) NSString *contentVideoID;
@end
@implementation YTPlayerViewController
@end
@interface YTInlineMutedPlaybackPlayerOverlayViewController : NSObject
@end
@implementation YTInlineMutedPlaybackPlayerOverlayViewController
@end
@compatibility_alias YouModRYDManager YouModDeArrowManager;
@interface YouModDeArrowManager (RYDStub)
- (void)fetchVotesForVideoID:(NSString *)videoID completion:(id)completion;
@end
@implementation YouModDeArrowManager (RYDStub)
- (void)fetchVotesForVideoID:(NSString *)videoID completion:(id)completion {}
@end
static __weak YTPlayerViewController *currentWatchPlayer;
static NSString *lastWatchVideoID;
/* WATCH_PLAYBACK */


@interface UICollectionViewCell : UIView
@end
@implementation UICollectionViewCell
@end
@interface _ASCollectionViewCell : UICollectionViewCell
@property(strong) ASDisplayNode *node;
@end
@implementation _ASCollectionViewCell
@end
@interface UICollectionView : UIView
@property(copy) NSArray *visibleCells;
- (void)layoutSubviews;
@end
@interface YTPlayerView : UIView
@end
@implementation YTPlayerView
@end
@interface YTMainAppPlayerOverlayView : UIView
@end
@implementation YTMainAppPlayerOverlayView
@end
static NSString *YouModCurrentWatchVideoID(void) { return currentWatchID; }
static NSString *YouModCurrentWatchTitle(void) { return [detailsID isEqual:currentWatchID] ? detailsTitle : nil; }
/* SCANNER_HELPERS */
@implementation UICollectionView
/* COLLECTION_HOOK */
@end

@interface TestLikeControl : UIView
@property(strong) UIView *watchRow;
- (void)youmod_refreshWatchBar:(NSNotification *)note;
@end
static UIView *YouModWatchRowForControl(TestLikeControl *like) { return like.watchRow; }
static void YMUpdateWatchBar(UIView *row) { YouModUpdateWatchTitlesForRow(row); }
@implementation TestLikeControl
/* WATCH_ROW_NOTIFICATION */
@end
static void drainUpdates(UIView *row) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(!objc_getAssociatedObject(row,"YMWatchTitleQueued"));
}
static FeedTextHook *titleNode(NSString *title) {
    FeedTextHook *node = [FeedTextHook new];
    node.layerBacked = YES;
    node.forbidParentAccess = YES;
    node.attributedText = [[NSAttributedString alloc] initWithString:title];
    return node;
}
static _ASCollectionViewCell *nodeCell(CGFloat y, NSArray *nodes) {
    _ASCollectionViewCell *cell = [_ASCollectionViewCell new];
    cell.frame = CGRectMake(0,y,393,80);
    cell.node = [ASDisplayNode new];
    cell.node.layerBacked = YES;
    cell.node.subnodes = nodes;
    return cell;
}
int main(void) { @autoreleasepool {
    NSAttributedString *native = [[NSAttributedString alloc] initWithString:@"ORIGINAL TITLE" attributes:@{
        NSFontAttributeName:@"native-font", NSForegroundColorAttributeName:@"native-color",
        @"NSAttachment":@"image", @"CTRunDelegate":@"glyph", @"NSGlyphInfo":@"arrow"}];
    NSAttributedString *clean = YouModDeArrowTitleText(native,@"A > B? Yes!");
    assert([clean.string isEqual:@"A > B? Yes!"] && [clean attributesAtIndex:0 effectiveRange:NULL].count == 2);
    assert([YouModCleanDeArrowTitle(@"  café\u00A0\uFFFC\u200Btest\n\t動画 👨‍👩‍👧‍👦 > 2! ") isEqual:@"café test 動画 👨‍👩‍👧‍👦 > 2!"]);
    assert(YouModCleanDeArrowTitle((id)NSNull.null) == nil);
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];

    currentWatchID = detailsID = @"WATCH000001";
    detailsTitle = @"Why Isn’t Heart Cancer a Thing?";
    manager.titles[currentWatchID] = @"Why is heart cancer so rare?";
    [manager.toggled addObject:currentWatchID];
    FeedTextHook *heading = titleNode(detailsTitle), *comment = titleNode(detailsTitle), *recommendation = titleNode(detailsTitle);
    UILabel *plain = [UILabel new];
    plain.text = detailsTitle; // Plain UIKit text has no attributedText yet.
    plain.font = @"native-font";
    _ASCollectionViewCell *header = nodeCell(0,@[heading]);
    UIView *row = [UIView new];
    row.window = YES;
    row.frame = CGRectMake(0,100,393,88);
    header.subviews = @[plain,row];
    UICollectionViewCell *commentCell = nodeCell(200,@[comment]), *feedCell = nodeCell(400,@[recommendation]);
    UICollectionView *collection = [UICollectionView new];
    collection.subviews = collection.visibleCells = @[header,commentCell,feedCell];
    TestLikeControl *like = [TestLikeControl new];
    like.watchRow = row;
    [[NSNotificationCenter defaultCenter] addObserver:like selector:@selector(youmod_refreshWatchBar:) name:kYMDeArrowUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:like selector:@selector(youmod_refreshWatchBar:) name:@"YouModWatchStatsChanged" object:nil];
    YTPlayerViewController *player = [YTPlayerViewController new];
    player.contentVideoID = currentWatchID;
    YouModWatchVideoChanged(player);
    drainUpdates(row);
    assert(![manager isOriginalToggledForVideoID:currentWatchID]);
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    assert([plain.text isEqual:manager.titles[currentWatchID]]);
    assert([comment.attributedText.string isEqual:detailsTitle] && [recommendation.attributedText.string isEqual:detailsTitle]);
    assert(heading.parentReads == 0);
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(row);
    assert([heading.attributedText.string isEqual:detailsTitle] && [plain.text isEqual:detailsTitle]);
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(row);
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    // Native text/CSS refreshes after binding must not silently restore the original.
    heading.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle attributes:@{NSForegroundColorAttributeName:@"new-theme"}];
    plain.text = detailsTitle;
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]] && [plain.text isEqual:manager.titles[currentWatchID]]);
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(row);
    assert([heading.attributedText.string isEqual:detailsTitle]);
    assert([[heading.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:@"new-theme"]);
    YTPlayerViewController *replacementPlayer = [YTPlayerViewController new];
    replacementPlayer.contentVideoID = currentWatchID;
    YouModWatchVideoChanged(replacementPlayer); drainUpdates(row);
    assert([manager isOriginalToggledForVideoID:currentWatchID]);

    // Title and controls may be separate cells, with no component owners or visible-state flags.
    FeedTextHook *separate = titleNode(detailsTitle);
    UICollectionViewCell *titleCell = nodeCell(0,@[separate]);
    header.frame = CGRectMake(0,80,393,188);
    collection.subviews = collection.visibleCells = @[titleCell,header,commentCell,feedCell];
    [collection layoutSubviews]; drainUpdates(row);
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(row);
    assert([separate.attributedText.string isEqual:manager.titles[currentWatchID]]);
    // Replacing a native title node while the action row survives must rebind it.
    FeedTextHook *newHeading = titleNode(detailsTitle);
    header.node.subnodes = @[newHeading];
    [collection layoutSubviews]; drainUpdates(row);
    assert([newHeading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    [newHeading didExitHierarchy];
    newHeading.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle];
    assert([newHeading.attributedText.string isEqual:detailsTitle]);
    [collection layoutSubviews]; drainUpdates(row);
    assert([newHeading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    // A bound node reused as a comment must drop the watch binding before doing parent work.
    newHeading.attributedText = [[NSAttributedString alloc] initWithString:@"An unrelated comment"];
    assert(!objc_getAssociatedObject(newHeading,"YMDeArrowWatchLabelVideoID"));
    assert([newHeading.attributedText.string isEqual:@"An unrelated comment"] && newHeading.parentReads == 0);
    header.node.subnodes = @[heading];

    YouModUpdateWatchTitlesForRow(row); // A pending pass must not swallow a new video's update.
    currentWatchID = @"WATCH000002";
    player.contentVideoID = currentWatchID;
    heading.attributedText = [[NSAttributedString alloc] initWithString:@"Next native title"];
    plain.text = @"Next native title";
    detailsID = @"WATCH000001"; // Previous playback's metadata must not brand the new title.
    YouModWatchVideoChanged(player); drainUpdates(row);
    assert([heading.attributedText.string isEqual:@"Next native title"]);
    detailsID = currentWatchID;
    detailsTitle = @"Next native title";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YouModWatchStatsChanged" object:nil]; drainUpdates(row);
    manager.titles[currentWatchID] = @"Late DeArrow title";
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":currentWatchID}]; drainUpdates(row);
    assert([heading.attributedText.string isEqual:@"Late DeArrow title"] && [plain.text isEqual:@"Late DeArrow title"]);
    NSString *status = objc_getAssociatedObject(row,"YMWatchTitleStatus");
    assert([status containsString:currentWatchID] && [status containsString:@"matched titles=2"]);
    preferences[DeArrowReplaceTitles] = NO;
    [collection layoutSubviews]; drainUpdates(row);
    assert([heading.attributedText.string isEqual:detailsTitle]);
    preferences[DeArrowReplaceTitles] = YES;
    for (int i=0; i<200; i++) {
        [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(row);
        NSString *expected = [manager isOriginalToggledForVideoID:currentWatchID] ? detailsTitle : manager.titles[currentWatchID];
        assert([heading.attributedText.string isEqual:expected]);
    }
    row.window = NO;
    NSString *detached = heading.attributedText.string;
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(row);
    assert([heading.attributedText.string isEqual:detached]);

    // The legacy UIKit cell also handles an absent renderer video ID.
    currentWatchID = detailsID = @"LEGACY00001";
    detailsTitle = @"(Privacy Not Included)";
    manager.titles[currentWatchID] = @"Criticisms of services that sponsor YouTubers";
    YouModDeArrowBeginWatchVideo(currentWatchID);
    YTSlimVideoInformationCell *legacy = [YTSlimVideoInformationCell new];
    legacy.window = YES;
    legacy.titleLabel = [TestLabel new];
    legacy.titleLabel.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle];
    [legacy didMoveToWindow];
    assert([legacy.titleLabel.attributedText.string isEqual:manager.titles[currentWatchID]]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([legacy.titleLabel.attributedText.string isEqual:detailsTitle]);

    FeedTextHook *fullscreen = titleNode(@"Unrelated fullscreen title");
    NSAttributedString *overlay = fullscreen.attributedText;
    manager.titleQueries = 0;
    for (int i=0; i<10000; i++) fullscreen.attributedText = overlay;
    assert(fullscreen.parentReads == 0 && manager.titleQueries == 0);
    manager.originals[@"FEEDHOOK001"] = @"Original feed title";
    manager.titles[@"FEEDHOOK001"] = @"Replacement feed title";
    fullscreen.forbidParentAccess = NO;
    objc_setAssociatedObject(fullscreen,"kYMDeArrowVideoIDKey",@"FEEDHOOK001",OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(fullscreen,"kYMDeArrowOrigAttrKey",[[NSAttributedString alloc] initWithString:@"Original feed title"],OBJC_ASSOCIATION_COPY_NONATOMIC);
    fullscreen.attributedText = [[NSAttributedString alloc] initWithString:@"Original feed title"];
    assert([fullscreen.attributedText.string isEqual:@"Replacement feed title"]);
} return 0; }
