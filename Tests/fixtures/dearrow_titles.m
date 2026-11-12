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
static NSString *descriptionTitleStatus;
static BOOL nativeDescriptionRendering;
@class ASDisplayNode;
static void YouModUpdateDescriptionTitle(ASDisplayNode *node);
/* TEXT_HELPERS */

@class ASDisplayNode;
@interface UIView : NSObject
@property(copy) NSString *accessibilityIdentifier;
@property(copy) NSString *accessibilityLabel;
@property BOOL window;
@property BOOL hidden;
@property BOOL userInteractionEnabled;
@property CGFloat alpha;
@property NSUInteger layoutRequests;
@property CGRect frame;
@property(readonly) CGRect bounds;
@property(weak) UIView *superview;
@property(copy) NSArray *subviews;
@property(strong) ASDisplayNode *keepalive_node;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (CGPoint)convertPoint:(CGPoint)point fromView:(UIView *)view;
- (void)setNeedsLayout;
@end
@implementation UIView
- (instancetype)init { if ((self = [super init])) { _userInteractionEnabled = YES; _alpha = 1; } return self; }
- (CGRect)bounds { return CGRectMake(0,0,self.frame.size.width,self.frame.size.height); }
- (void)setSubviews:(NSArray *)views { _subviews = [views copy]; for (UIView *v in views) v.superview = self; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    for (UIView *p=self; p && p != view; p=p.superview) rect = CGRectOffset(rect,p.frame.origin.x,p.frame.origin.y);
    return rect;
}
- (CGPoint)convertPoint:(CGPoint)point fromView:(UIView *)view { assert(view == self.superview); return CGPointMake(point.x-self.frame.origin.x,point.y-self.frame.origin.y); }
- (void)setNeedsLayout { self.layoutRequests++; }
@end
@class UIEvent;
@interface UIButton : UIView
@property BOOL enabled;
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event;
@end
@implementation UIButton
- (instancetype)init { if ((self = [super init])) _enabled = YES; return self; }
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return CGRectContainsPoint(self.bounds,point); }
@end
@interface YouModDeArrowButton : UIButton
@end
@implementation YouModDeArrowButton
/* BUTTON_HIT_AREA */
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
- (void)layout;
@property BOOL isNodeLoaded;
@property NSUInteger layoutRequests;
- (void)setNeedsLayout;
@property BOOL layerBacked;
@property(weak) ASDisplayNode *supernode;
@property(strong) UIView *view;
@property CGRect bounds;
@property CGRect frame;
@property BOOL hidden;
@property(copy) NSArray *subnodes;
@property(copy) NSArray *yogaChildren;
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node;
@end
@implementation ASDisplayNode
/* DESCRIPTION_NODE_HOOKS */
- (void)setNeedsLayout { self.layoutRequests++; }
- (UIView *)view { assert(!self.layerBacked); return _view; }
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node {
    for (ASDisplayNode *p=self; p && p != node; p=p.supernode) rect = CGRectOffset(rect,p.frame.origin.x,p.frame.origin.y);
    return rect;
}
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
- (NSAttributedString *)attributedText { assert(!nativeDescriptionRendering); return self.rawAttributedText; }
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


static BOOL nativeFeedLayout;
static NSUInteger feedUpdates, voteUpdates;
/* FEED_IDENTIFIERS */
static void YouModApplyFeedDeArrow(UIView *menu) {
    assert(!nativeFeedLayout);
    if (menu.window && IS_ENABLED(DeArrowEnabled) && YouModIsOverflowButtonView(menu)) feedUpdates++;
}
static void YMApplyFeedVotes(UIView *menu) {
    assert(!nativeFeedLayout);
    if (menu.window && YouModIsOverflowButtonView(menu)) voteUpdates++;
}
/* FEED_QUEUES */
@interface FeedMenuHook : UIView
- (void)layoutSubviews;
@end
@implementation FeedMenuHook
/* FEED_LAYOUT */
@end

@interface UICollectionViewCell : UIView
@property(strong) NSIndexPath *sourceIndexPath;
- (void)layoutSubviews;
@end
@implementation UICollectionViewCell
/* FEED_CELL_LAYOUT */
@end
@interface _ASCollectionViewCell : UICollectionViewCell
@property(strong) ASDisplayNode *node;
@property(strong) UIView *nativeHitView;
@property BOOL nativeAnimating;
- (BOOL)isAnimating;
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
@end
@implementation _ASCollectionViewCell
- (BOOL)isAnimating { return self.nativeAnimating; }
/* CELL_HIT_TEST */
@end
@interface NSIndexPath (CollectionPosition)
@property(readonly) NSUInteger section;
@property(readonly) NSUInteger item;
@end
@implementation NSIndexPath (CollectionPosition)
- (NSUInteger)section { return [self indexAtPosition:0]; }
- (NSUInteger)item { return [self indexAtPosition:1]; }
@end
@interface UICollectionView : UIView
@property(copy) NSArray *visibleCells;
- (void)layoutSubviews;
- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell;
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
- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell { return cell.sourceIndexPath; }
/* COLLECTION_HOOK */
@end

@interface ELMComponent : NSObject
@property(copy) NSString *templateURI;
@property(strong) ASDisplayNode *pendingNode;
@property BOOL nativeReady;
- (instancetype)initWithElement:(id)element context:(id)context treeLocalContext:(id)treeLocalContext;
- (ASDisplayNode *)node;
- (ASDisplayNode *)materializeNativeNode;
@end
/* DESCRIPTION_HELPERS */
@implementation ELMComponent
- (ASDisplayNode *)materializeNativeNode { self.nativeReady = YES; return self.pendingNode; }
/* DESCRIPTION_COMPONENT_HOOKS */
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
static void drainUpdates(id row) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(!objc_getAssociatedObject(row,"YMWatchTitleQueued"));
    assert(!objc_getAssociatedObject(row,"YMDescriptionTitleQueued"));
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
    cell.sourceIndexPath = [NSIndexPath indexPathWithIndexes:(NSUInteger[]){0,0} length:2];
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

    // Replay the report with a component that has no text controller until node is requested.
    row.window = NO;
    currentWatchID = detailsID = @"1FurWDiK9A4";
    detailsTitle = @"Did Anthropic just save its $1 trillion IPO?";
    manager.originals[currentWatchID] = detailsTitle;
    manager.titles[currentWatchID] = @"Fable 5.2 Review";
    [manager.toggled removeObject:currentWatchID];
    ASDisplayNode *description = [ASDisplayNode new];
    description.layerBacked = YES; // Never request a UIView from the flattened header.
    FeedTextHook *expanded = titleNode(detailsTitle), *body = titleNode(detailsTitle);
    expanded.forbidParentAccess = body.forbidParentAccess = NO;
    expanded.frame = CGRectMake(0,20,340,90); expanded.bounds = CGRectMake(0,0,340,90);
    body.frame = CGRectMake(0,240,340,90); body.bounds = CGRectMake(0,0,340,90);
    expanded.supernode = body.supernode = description;
    description.subnodes = @[body,expanded]; // Traversal order is not the visual order.
    ELMComponent *descriptionHeader = [[ELMComponent alloc] initWithElement:description context:@"video_description_header.eml|80d1782e180cb1b" treeLocalContext:nil];
    assert(!descriptionHeader.nativeReady && !objc_getAssociatedObject(description,"YMDescriptionHeaderRoot"));
    drainUpdates(description);
    assert([expanded.attributedText.string isEqual:detailsTitle]);
    nativeDescriptionRendering = YES;
    assert(descriptionHeader.node == description);
    assert([expanded.rawAttributedText.string isEqual:detailsTitle]);
    [description layout]; // Native rendering must finish before reading or changing text.
    nativeDescriptionRendering = NO;
    drainUpdates(description);
    assert([expanded.attributedText.string isEqual:manager.titles[currentWatchID]]);
    assert([body.attributedText.string isEqual:detailsTitle]);
    assert([descriptionTitleStatus containsString:@"matched=1"]);
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(description);
    assert([expanded.attributedText.string isEqual:detailsTitle]);
    FeedTextHook *originalPanelTitle = titleNode(detailsTitle);
    ELMComponent *originalPanel = [[ELMComponent alloc] initWithElement:originalPanelTitle context:@"video_description_header.eml-js" treeLocalContext:nil];
    assert(originalPanel.node == originalPanelTitle); drainUpdates(originalPanelTitle);
    assert([originalPanelTitle.attributedText.string isEqual:detailsTitle]);
    [expanded didExitHierarchy];
    assert(!objc_getAssociatedObject(expanded,"YMDeArrowWatchLabelVideoID"));
    [descriptionHeader node]; drainUpdates(description);
    assert([manager isOriginalToggledForVideoID:currentWatchID] && [expanded.attributedText.string isEqual:detailsTitle]);
    [manager toggleDeArrowForVideoID:currentWatchID]; drainUpdates(description);
    assert([expanded.attributedText.string isEqual:manager.titles[currentWatchID]]);
    expanded.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle];
    assert([expanded.attributedText.string isEqual:manager.titles[currentWatchID]]);

    // A new native tree on reopen gets its own binding, including hashed resource names.
    ASDisplayNode *reopened = [ASDisplayNode new];
    FeedTextHook *reopenedTitle = titleNode(detailsTitle);
    reopened.subnodes = @[reopenedTitle];
    reopenedTitle.forbidParentAccess = NO;
    reopenedTitle.supernode = reopened;
    ELMComponent *newHeader = [[ELMComponent alloc] initWithElement:reopened context:@"youtube://components/video_description_header.eml_80d1782e180cb1b" treeLocalContext:nil];
    assert(!newHeader.nativeReady);
    assert(newHeader.node == reopened); drainUpdates(reopened);
    assert([reopenedTitle.attributedText.string isEqual:manager.titles[currentWatchID]]);
    NSUInteger requests = description.layoutRequests;
    for (int i=0; i<200; i++) [description layout];
    drainUpdates(description);
    assert(description.layoutRequests == requests); // Stable text cannot create a layout loop.

    // Comments and the description body never acquire a binding, even for identical text.
    for (NSString *uri in @[@"comments_header.eml|1", @"description_body.eml|f1087e40a7108802", @"video_metadata_carousel.eml|2"]) {
        ASTextNode *unrelated = titleNode(detailsTitle);
        ELMComponent *component = [[ELMComponent alloc] initWithElement:unrelated context:uri treeLocalContext:nil];
        assert(component.node == unrelated);
        [unrelated layout]; drainUpdates(unrelated);
        assert([unrelated.attributedText.string isEqual:detailsTitle]);
        assert(!objc_getAssociatedObject(unrelated,"YMDescriptionObserved"));
    }

    // New playback data and late branding must not rewrite a stale header.
    currentWatchID = detailsID = @"PANEL000001";
    detailsTitle = @"An original full title";
    FeedTextHook *lateTitle = titleNode(detailsTitle);
    ASDisplayNode *late = lateTitle;
    ELMComponent *lateHeader = [[ELMComponent alloc] initWithElement:late context:@"video_description_header.eml" treeLocalContext:nil];
    assert(lateHeader.node == late);
    [late layout]; drainUpdates(late);
    assert([lateTitle.attributedText.string isEqual:detailsTitle]);
    NSString *stale = expanded.attributedText.string;
    manager.titles[currentWatchID] = @"A later DeArrow full title";
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":currentWatchID}]; drainUpdates(late);
    assert([lateTitle.attributedText.string isEqual:@"A later DeArrow full title"]);
    assert([expanded.attributedText.string isEqual:stale]);
    preferences[DeArrowReplaceTitles] = NO;
    [late layout]; drainUpdates(late);
    assert([lateTitle.attributedText.string isEqual:detailsTitle]);
    preferences[DeArrowReplaceTitles] = YES;
    [late layout]; drainUpdates(late);
    assert([lateTitle.attributedText.string isEqual:@"A later DeArrow full title"]);

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

    // Texture's native cell hit-test forwards into its node and ignores our sibling.
    // The production hook must return the accessory across its real 44pt target.
    _ASCollectionViewCell *feedTarget = nodeCell(0,@[]);
    feedTarget.frame = CGRectMake(0,0,393,310);
    feedTarget.nativeHitView = [UIView new];
    UIView *menu = [UIView new];
    YouModDeArrowButton *toggle = [YouModDeArrowButton new];
    toggle.frame = CGRectMake(342,262,44,44);
    toggle.window = YES;
    feedTarget.subviews = @[menu,toggle];
    NSHashTable *menus = [NSHashTable weakObjectsHashTable];
    [menus addObject:menu];
    objc_setAssociatedObject(feedTarget,"YMDeArrowFeedMenus",menus,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(menu,"kYMDeArrowButton",toggle,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    assert([feedTarget hitTest:CGPointMake(343,263) withEvent:nil] == toggle);
    assert([feedTarget hitTest:CGPointMake(385,305) withEvent:nil] == toggle);
    assert([feedTarget hitTest:CGPointMake(350,240) withEvent:nil] == feedTarget.nativeHitView); // More stays native.
    assert([feedTarget hitTest:CGPointMake(100,100) withEvent:nil] == feedTarget.nativeHitView); // Video stays native.
    toggle.enabled = NO;
    assert([feedTarget hitTest:CGPointMake(360,280) withEvent:nil] == feedTarget.nativeHitView);
    toggle.enabled = YES; toggle.hidden = YES;
    assert([feedTarget hitTest:CGPointMake(360,280) withEvent:nil] == feedTarget.nativeHitView);
    toggle.hidden = NO;
    feedTarget.nativeAnimating = YES;
    assert([feedTarget hitTest:CGPointMake(360,280) withEvent:nil] == feedTarget.nativeHitView);
    feedTarget.nativeAnimating = NO;
    // Compact notification layout uses the same cell hit path.
    feedTarget.frame = CGRectMake(0,0,393,98);
    toggle.frame = CGRectMake(347,36,44,44);
    assert([feedTarget hitTest:CGPointMake(348,37) withEvent:nil] == toggle);
    assert([feedTarget hitTest:CGPointMake(390,79) withEvent:nil] == toggle);
    assert([feedTarget hitTest:CGPointMake(370,20) withEvent:nil] == feedTarget.nativeHitView);
    preferences[DeArrowEnabled] = NO;
    assert([feedTarget hitTest:CGPointMake(370,60) withEvent:nil] == feedTarget.nativeHitView);
    preferences[DeArrowEnabled] = YES;

    // Accessory work must escape native collection layout, coalesce, and recheck reuse.
    FeedMenuHook *notificationMenu = [FeedMenuHook new];
    notificationMenu.window = YES;
    notificationMenu.accessibilityIdentifier = @"eml.overflow_button";
    NSHashTable *notificationMenus = [NSHashTable weakObjectsHashTable];
    [notificationMenus addObject:notificationMenu];
    objc_setAssociatedObject(feedTarget,"YMDeArrowFeedMenus",notificationMenus,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    nativeFeedLayout = YES;
    for (int i=0; i<200; i++) {
        [feedTarget layoutSubviews];
        [notificationMenu layoutSubviews];
        YMUpdateFeedVotes(notificationMenu);
    }
    assert(feedUpdates == 0 && voteUpdates == 0 && notificationMenu.layoutRequests == 0);
    notificationMenu.window = NO; // A tap navigated away before deferred work can run.
    nativeFeedLayout = NO;
    drainUpdates(notificationMenu);
    assert(feedUpdates == 0 && voteUpdates == 0);
    notificationMenu.window = YES;
    [notificationMenu layoutSubviews];
    YMUpdateFeedVotes(notificationMenu);
    drainUpdates(notificationMenu);
    assert(feedUpdates == 1 && voteUpdates == 1);
    notificationMenu.accessibilityIdentifier = @"unrelated recycled view";
    [notificationMenu layoutSubviews]; YMUpdateFeedVotes(notificationMenu);
    drainUpdates(notificationMenu);
    assert(feedUpdates == 1 && voteUpdates == 1);
    __weak UIView *releasedMenu;
    @autoreleasepool {
        FeedMenuHook *temporary = [FeedMenuHook new]; temporary.window = YES;
        temporary.accessibilityIdentifier = @"eml.overflow_button";
        releasedMenu = temporary;
        [temporary layoutSubviews]; YMUpdateFeedVotes(temporary);
    }
    assert(releasedMenu == nil);
    drainUpdates(nil);
    assert(feedUpdates == 1 && voteUpdates == 1);

    FeedTextHook *fullscreen = titleNode(@"Unrelated fullscreen title");
    NSAttributedString *overlay = fullscreen.attributedText;
    manager.titleQueries = 0;
    for (int i=0; i<10000; i++) { fullscreen.attributedText = overlay; [fullscreen layout]; }
    assert(fullscreen.parentReads == 0 && manager.titleQueries == 0);
    manager.originals[@"FEEDHOOK001"] = @"Original feed title";
    manager.titles[@"FEEDHOOK001"] = @"Replacement feed title";
    fullscreen.forbidParentAccess = NO;
    objc_setAssociatedObject(fullscreen,"kYMDeArrowVideoIDKey",@"FEEDHOOK001",OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(fullscreen,"kYMDeArrowOrigAttrKey",[[NSAttributedString alloc] initWithString:@"Original feed title"],OBJC_ASSOCIATION_COPY_NONATOMIC);
    fullscreen.attributedText = [[NSAttributedString alloc] initWithString:@"Original feed title"];
    assert([fullscreen.attributedText.string isEqual:@"Replacement feed title"]);
} return 0; }
