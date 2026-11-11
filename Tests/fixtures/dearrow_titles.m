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

@interface NSValue (Geometry)
@property(readonly) CGRect CGRectValue;
+ (instancetype)valueWithCGRect:(CGRect)rect;
@end
@implementation NSValue (Geometry)
+ (instancetype)valueWithCGRect:(CGRect)rect { return [self valueWithBytes:&rect objCType:@encode(CGRect)]; }
- (CGRect)CGRectValue { CGRect rect; [self getValue:&rect size:sizeof(rect)]; return rect; }
@end
@interface UIBezierPath : NSObject
@property CGRect rect;
+ (instancetype)bezierPathWithRect:(CGRect)rect;
@end
@implementation UIBezierPath
+ (instancetype)bezierPathWithRect:(CGRect)rect { UIBezierPath *p = [self new]; p.rect = rect; return p; }
@end
@interface UIView : NSObject
@property BOOL window;
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;
@end
@implementation UIView
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view { return rect; }
@end
@class ELMNodeController;
@interface ASDisplayNode : NSObject
@property BOOL isNodeLoaded;
@property BOOL layerBacked;
@property(strong) ASDisplayNode *supernode;
@property(strong) UIView *view;
@property CGRect bounds;
@property(copy) NSArray *subnodes;
@property(copy) NSArray *yogaChildren;
@property(strong) ELMNodeController *nodeController;
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node;
@end
@implementation ASDisplayNode
- (UIView *)view { assert(!self.layerBacked); return _view; }
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node { return rect; }
@end
@interface ASTextNode : ASDisplayNode
@property(copy) NSAttributedString *attributedText;
@property(copy) NSArray *exclusionPaths;
@property NSUInteger assignments;
@end
@interface ASNetworkImageNode : ASDisplayNode
@end
@implementation ASNetworkImageNode
@end
@implementation ASTextNode
- (void)setExclusionPaths:(NSArray *)paths { _exclusionPaths = [paths copy]; self.assignments++; }
@end
/* EXCLUSION_HELPER */

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
static void YouModCollectNodesFromView(NSArray *labels, NSMutableArray *texts, NSMutableArray *images) {
    [texts addObjectsFromArray:labels];
}
/* WATCH_BINDING */

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

@interface ELMComponent : NSObject
@property(copy) NSString *templateURI;
@property(strong) ELMComponent *owningComponent;
@end
@implementation ELMComponent
@end
@interface ELMNodeController : NSObject
@property(strong) ELMComponent *owningComponent;
@end
@implementation ELMNodeController
@end
@interface ELMTextNode : ASTextNode
@property BOOL visible;
@property NSUInteger feedUpdates;
- (BOOL)isVisible;
- (void)didEnterVisibleState;
- (void)didExitVisibleState;
- (void)updateAttributedText;
@end
static NSString *YouModCurrentWatchVideoID(void) { return currentWatchID; }
static NSString *YouModCurrentWatchTitle(void) {
    if (![detailsID isEqual:currentWatchID]) return nil;
    return detailsTitle;
}
/* ELEMENTS_HELPERS */
@implementation ELMTextNode
- (BOOL)isVisible { return self.visible; }
- (void)feedTitleUpdated:(NSNotification *)note { self.feedUpdates++; }
/* ELEMENTS_HOOKS */
@end
static ELMTextNode *titleNode(NSString *title, NSString *uri) {
    ELMTextNode *node = [ELMTextNode new];
    node.attributedText = [[NSAttributedString alloc] initWithString:title];
    node.layerBacked = YES;
    node.visible = YES;
    node.nodeController = [ELMNodeController new];
    node.nodeController.owningComponent = [ELMComponent new];
    node.nodeController.owningComponent.templateURI = uri;
    return node;
}

static void drainTextUpdate(ELMTextNode *node) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:1];
    while (objc_getAssociatedObject(node,"YMWatchTitleQueued") && limit.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    assert(!objc_getAssociatedObject(node,"YMWatchTitleQueued"));
}

int main(void) { @autoreleasepool {
    NSAttributedString *native = [[NSAttributedString alloc] initWithString:@"ORIGINAL\uFFFC TITLE" attributes:@{
        NSFontAttributeName: @"native-font", NSForegroundColorAttributeName: @"native-color",
        @"NSAttachment": @"image", @"CTRunDelegate": @"glyph", @"NSGlyphInfo": @"arrow"
    }];
    NSAttributedString *clean = YouModDeArrowTitleText(native, @"A > B? Yes!");
    assert([clean.string isEqual:@"A > B? Yes!"]);
    assert([[clean attributesAtIndex:0 effectiveRange:NULL] count] == 2);
    assert([[clean attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL] isEqual:@"native-font"]);
    assert([YouModCleanDeArrowTitle(@"  café\u00A0\uFFFC\u200Btest\n\t動画 👨‍👩‍👧‍👦 > 2! ") isEqual:@"café test 動画 👨‍👩‍👧‍👦 > 2!"]);
    assert(YouModCleanDeArrowTitle((id)NSNull.null) == nil);
    YTSlimVideoInformationCell *cell = [YTSlimVideoInformationCell new];
    cell.window = YES;
    cell.titleLabel = [TestLabel new];
    cell.titleLabel.attributedText = native;
    TestLabel *experimental = [TestLabel new];
    experimental.attributedText = native;
    cell.experimentalTitleLabel = @[experimental];
    NSString *firstID = @"abcdefghijk", *nextID = @"12345678901";
    objc_setAssociatedObject(cell, "YMWatchTitleVideoID", firstID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
    // Legacy cell labels still support late completion and the original toggle.
    YouModUpdateWatchTitle(cell);
    assert(cell.titleLabel.attributedText == native);
    manager.titles[firstID] = @"DeArrow title";
    YouModUpdateWatchTitle(cell);
    assert([cell.titleLabel.attributedText.string isEqual:@"DeArrow title"]);
    assert([experimental.attributedText.string isEqual:@"DeArrow title"]);
    cell.experimentalTitleLabel = experimental; // The legacy experiment uses YTLabel.
    YouModUpdateWatchTitle(cell);
    assert([experimental.attributedText.string isEqual:@"DeArrow title"]);
    [manager.toggled addObject:firstID];
    YouModUpdateWatchTitle(cell);
    assert(cell.titleLabel.attributedText == native && experimental.attributedText == native);
    [manager.toggled removeObject:firstID];
    YouModUpdateWatchTitle(cell);
    preferences[DeArrowReplaceTitles] = NO;
    YouModUpdateWatchTitle(cell);
    assert(cell.titleLabel.attributedText == native);
    preferences[DeArrowReplaceTitles] = YES;
    cell.window = NO;
    manager.titles[firstID] = @"Late result on a detached cell";
    YouModUpdateWatchTitle(cell);
    assert(cell.titleLabel.attributedText == native);
    cell.window = YES;
    NSAttributedString *next = [[NSAttributedString alloc] initWithString:@"NEXT VIDEO"];
    cell.titleLabel.attributedText = next;
    experimental.attributedText = next;
    objc_setAssociatedObject(cell, "YMWatchTitleVideoID", nextID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    YouModUpdateWatchTitle(cell);
    assert([manager.originals[nextID] isEqual:@"NEXT VIDEO"]);
    assert(cell.titleLabel.attributedText == next);
    manager.titles[nextID] = @"Second replacement";
    YouModUpdateWatchTitle(cell);
    assert([cell.titleLabel.attributedText.string isEqual:@"Second replacement"]);
    assert([manager.originals[firstID] isEqual:native.string]);
    // A renderer may have replaced the string before its label is first bound.
    NSString *prefetchedID = @"ABCDEFGHIJK";
    manager.originals[prefetchedID] = @"RAW ORIGINAL TITLE";
    manager.titles[prefetchedID] = @"Prefetched DeArrow";
    cell.titleLabel.attributedText = [[NSAttributedString alloc] initWithString:manager.titles[prefetchedID]];
    cell.experimentalTitleLabel = nil;
    objc_setAssociatedObject(cell, "YMWatchTitleVideoID", prefetchedID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    YouModUpdateWatchTitle(cell);
    [manager.toggled addObject:prefetchedID];
    YouModUpdateWatchTitle(cell);
    assert([cell.titleLabel.attributedText.string isEqual:@"RAW ORIGINAL TITLE"]);
    ASTextNode *text = [ASTextNode new];
    text.bounds = CGRectMake(0,0,300,60);
    text.layerBacked = YES;
    text.isNodeLoaded = YES;
    ASDisplayNode *anchor = [ASDisplayNode new];
    anchor.isNodeLoaded = YES;
    anchor.view = [UIView new];
    anchor.view.window = YES;
    text.supernode = anchor;
    UIBezierPath *nativePath = [UIBezierPath new];
    text.exclusionPaths = @[nativePath];
    text.assignments = 0;
    CGRect hit = CGRectMake(270,0,44,44);
    YouModReserveToggleText(@[text], anchor.view, hit, YES);
    assert(text.assignments == 1 && text.exclusionPaths.count == 2);
    YouModReserveToggleText(@[text], anchor.view, hit, YES);
    assert(text.assignments == 1); // Stable layout must not invalidate text again.
    anchor.view.window = NO;
    YouModReserveToggleText(@[text], nil, CGRectZero, NO);
    assert(text.assignments == 2 && text.exclusionPaths.count == 1);
    assert(text.exclusionPaths.firstObject == nativePath); // Restore even after detach/disable.

    // Modern header: the leaf owns the component; no collection-cell owner exists.
    currentWatchID = detailsID = @"WATCH000001";
    detailsTitle = @"Original watch title";
    manager.titles[currentWatchID] = @"Overview and criticisms of the NYT vs. Brave case";
    [manager.toggled addObject:currentWatchID];
    ELMTextNode *heading = titleNode(detailsTitle, @"video_metadata.eml|3035ad7f9a19183f");
    ELMTextNode *comment = titleNode(detailsTitle, @"comment.eml|test");
    ELMTextNode *recommendation = titleNode(detailsTitle, @"video_with_context.eml|test");
    ASDisplayNode *outer = [ASDisplayNode new];
    heading.supernode = comment.supernode = recommendation.supernode = outer;
    assert(!YouModIsWatchMetadataNode(outer));
    [heading didEnterVisibleState];
    [comment didEnterVisibleState];
    [recommendation didEnterVisibleState];
    [[NSNotificationCenter defaultCenter] addObserver:recommendation selector:@selector(feedTitleUpdated:) name:kYMDeArrowUpdatedNotification object:nil];
    [recommendation didExitVisibleState]; // Watch cleanup must preserve a feed observer.
    YTPlayerViewController *player = [YTPlayerViewController new];
    player.contentVideoID = currentWatchID;
    YouModWatchVideoChanged(player);
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    assert([comment.attributedText.string isEqual:detailsTitle] && [recommendation.attributedText.string isEqual:detailsTitle]);
    assert(![manager isOriginalToggledForVideoID:currentWatchID]);
    assert(recommendation.feedUpdates == 1);
    [[NSNotificationCenter defaultCenter] removeObserver:recommendation name:kYMDeArrowUpdatedNotification object:nil];
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    YTPlayerViewController *replacementPlayer = [YTPlayerViewController new];
    replacementPlayer.contentVideoID = currentWatchID;
    YouModWatchVideoChanged(replacementPlayer);
    assert([manager isOriginalToggledForVideoID:currentWatchID]);
    [heading updateAttributedText]; drainTextUpdate(heading);
    assert([heading.attributedText.string isEqual:detailsTitle]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    heading.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle attributes:@{NSForegroundColorAttributeName:@"new-theme"}];
    [heading updateAttributedText]; drainTextUpdate(heading);
    assert([[heading.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:@"new-theme"]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:detailsTitle]);

    currentWatchID = @"WATCH000002";
    player.contentVideoID = currentWatchID;
    YouModWatchVideoChanged(player);
    heading.attributedText = [[NSAttributedString alloc] initWithString:@"Next native title"];
    [heading updateAttributedText]; drainTextUpdate(heading); // Player details still belong to the old video.
    assert([heading.attributedText.string isEqual:@"Next native title"]);
    detailsID = currentWatchID;
    detailsTitle = @"Next native title";
    heading.nodeController.owningComponent.templateURI = @"yt://video_metadata_inner.eml-js|test";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YouModWatchStatsChanged" object:nil];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    manager.titles[currentWatchID] = @"Late DeArrow title";
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":@"WATCH000001"}];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":currentWatchID}];
    assert([heading.attributedText.string isEqual:@"Late DeArrow title"]);
    preferences[DeArrowReplaceTitles] = NO;
    [heading updateAttributedText]; drainTextUpdate(heading);
    assert([heading.attributedText.string isEqual:detailsTitle]);
    preferences[DeArrowReplaceTitles] = YES;
    heading.visible = NO;
    [heading didExitVisibleState];
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    assert(!objc_getAssociatedObject(heading,"YMWatchTitleObserved"));
    heading.visible = YES;
    heading.nodeController.owningComponent.templateURI = @"comment.eml|recycled";
    [heading didEnterVisibleState];
    assert(!objc_getAssociatedObject(heading,"YMWatchTitleObserved"));
    assert([heading.attributedText.string isEqual:detailsTitle]);

    ELMComponent *cycle = heading.nodeController.owningComponent;
    cycle.owningComponent = cycle;
    assert(!YouModIsWatchMetadataNode(heading));
    ELMComponent *second = [ELMComponent new];
    second.templateURI = @"video_with_context.eml|test";
    cycle.owningComponent = second;
    second.owningComponent = cycle;
    assert(!YouModIsWatchMetadataNode(heading));
    cycle.owningComponent = nil;
    second.owningComponent = nil;

    // Native setCell:/setVideoID: are optional. Exercise actual window and
    // notification callbacks without pre-seeding a title-cell video ID.
    currentWatchID = detailsID = @"LEGACY00001";
    detailsTitle = @"(Privacy Not Included)";
    heading.visible = NO;
    [heading didExitVisibleState];
    manager.titles[currentWatchID] = @"Criticisms of services that sponsor YouTubers";
    [manager.toggled addObject:currentWatchID];
    player.contentVideoID = currentWatchID;
    YouModWatchVideoChanged(player);
    YTSlimVideoInformationCell *unbound = [YTSlimVideoInformationCell new];
    unbound.window = YES;
    unbound.titleLabel = [TestLabel new];
    unbound.titleLabel.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle];
    [unbound didMoveToWindow];
    assert(objc_getAssociatedObject(unbound, "YMWatchTitleVideoID") == nil);
    assert([unbound.titleLabel.attributedText.string isEqual:manager.titles[currentWatchID]]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([unbound.titleLabel.attributedText.string isEqual:detailsTitle]);
    [unbound layoutSubviews];
    assert([unbound.titleLabel.attributedText.string isEqual:detailsTitle]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([unbound.titleLabel.attributedText.string isEqual:manager.titles[currentWatchID]]);
    for (int i=0; i<200; i++) {
        unbound.window = NO;
        [unbound didMoveToWindow];
        NSString *detached = unbound.titleLabel.attributedText.string;
        [manager toggleDeArrowForVideoID:currentWatchID];
        assert([unbound.titleLabel.attributedText.string isEqual:detached]);
        unbound.window = YES;
        [unbound didMoveToWindow];
        NSString *expected = [manager isOriginalToggledForVideoID:currentWatchID] ? detailsTitle : manager.titles[currentWatchID];
        assert([unbound.titleLabel.attributedText.string isEqual:expected]);
    }
    // Elements also must not require player details when a feed cached the original.
    detailsID = @"PENDING0001";
    heading.visible = YES;
    heading.nodeController.owningComponent.templateURI = @"video_metadata.eml|3035ad7f9a19183f";
    heading.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle];
    [heading updateAttributedText]; drainTextUpdate(heading);
    NSString *expected = [manager isOriginalToggledForVideoID:currentWatchID] ? detailsTitle : manager.titles[currentWatchID];
    assert([heading.attributedText.string isEqual:expected]);
    FeedTextHook *fullscreen = [FeedTextHook new];
    fullscreen.forbidParentAccess = YES;
    NSAttributedString *overlayTitle = [[NSAttributedString alloc] initWithString:@"Unrelated fullscreen title"];
    manager.titleQueries = 0;
    for (int i=0; i<10000; i++) fullscreen.attributedText = overlayTitle;
    assert(fullscreen.parentReads == 0 && manager.titleQueries == 0);
    assert(fullscreen.attributedText == overlayTitle);
    objc_setAssociatedObject(fullscreen, "kYMDeArrowVideoIDKey", @"FEEDHOOK001", OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(fullscreen, "kYMDeArrowOrigAttrKey", [[NSAttributedString alloc] initWithString:@"Old feed title"], OBJC_ASSOCIATION_COPY_NONATOMIC);
    fullscreen.attributedText = overlayTitle;
    assert(fullscreen.parentReads == 0 && objc_getAssociatedObject(fullscreen, "kYMDeArrowVideoIDKey") == nil);
    fullscreen.forbidParentAccess = NO;
    NSAttributedString *feedTitle = [[NSAttributedString alloc] initWithString:@"Original feed title"];
    manager.originals[@"FEEDHOOK001"] = feedTitle.string;
    manager.titles[@"FEEDHOOK001"] = @"Replacement feed title";
    objc_setAssociatedObject(fullscreen, "kYMDeArrowVideoIDKey", @"FEEDHOOK001", OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(fullscreen, "kYMDeArrowOrigAttrKey", feedTitle, OBJC_ASSOCIATION_COPY_NONATOMIC);
    fullscreen.attributedText = feedTitle;
    assert([fullscreen.attributedText.string isEqual:@"Replacement feed title"] && fullscreen.parentReads == 1);
} return 0; }
