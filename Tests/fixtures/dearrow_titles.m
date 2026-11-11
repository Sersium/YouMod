#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
#define NSFontAttributeName @"NSFont"
#define NSForegroundColorAttributeName @"NSColor"
#define NSParagraphStyleAttributeName @"NSParagraphStyle"
#define DeArrowEnabled 0
#define DeArrowReplaceTitles 1
static BOOL preferences[] = {YES, YES};
#define IS_ENABLED(key) preferences[key]
static NSString * const kYMDeArrowUpdatedNotification = @"YouModDeArrowUpdatedNotification";
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
@end
@implementation YTSlimVideoInformationCell
@end
@interface YouModDeArrowManager : NSObject
@property(strong) NSMutableDictionary *originals;
@property(strong) NSMutableDictionary *titles;
@property(strong) NSMutableSet *toggled;
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
- (NSString *)titleForVideoID:(NSString *)videoID { return [self.toggled containsObject:videoID] ? self.originals[videoID] : self.titles[videoID]; }
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
@interface UICollectionViewCell : NSObject
@end
@implementation UICollectionViewCell
@end
@interface _ASCollectionViewCell : UICollectionViewCell
@property(strong) ASDisplayNode *node;
@end
@implementation _ASCollectionViewCell
@end
@interface UICollectionView : NSObject
@property(copy) NSArray *visibleCells;
@end
@implementation UICollectionView
@end
@interface YTWatchNextResultsViewController : NSObject
@property(strong) UIView *viewIfLoaded;
@property(strong) UICollectionView *collectionView;
- (void)viewDidLoad;
- (void)viewDidLayoutSubviews;
- (void)collectionView:(UICollectionView *)view willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path;
@end
static NSString *currentWatchID, *detailsID, *detailsTitle;
static NSString *YouModCurrentWatchVideoID(void) { return currentWatchID; }
static NSString *YouModCurrentWatchTitle(void) {
    if (![detailsID isEqual:currentWatchID]) return nil;
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
    [manager registerOriginalTitle:detailsTitle forVideoID:currentWatchID];
    return [manager titleForVideoID:currentWatchID] ?: detailsTitle;
}
/* ELEMENTS_HELPERS */
@implementation YTWatchNextResultsViewController
/* ELEMENTS_HOOKS */
@end

static _ASCollectionViewCell *metadataCell(NSString *uri, NSArray *texts) {
    _ASCollectionViewCell *cell = [_ASCollectionViewCell new];
    cell.node = [ASDisplayNode new];
    cell.node.layerBacked = YES; // Binding must never materialize a UIView.
    cell.node.subnodes = texts;
    cell.node.nodeController = [ELMNodeController new];
    cell.node.nodeController.owningComponent = [ELMComponent new];
    cell.node.nodeController.owningComponent.templateURI = uri;
    return cell;
}
static ASTextNode *titleNode(NSString *title) {
    ASTextNode *node = [ASTextNode new];
    node.attributedText = [[NSAttributedString alloc] initWithString:title];
    node.layerBacked = YES;
    return node;
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

    // The reported watch layout has an Elements cell, with no legacy title cell.
    currentWatchID = detailsID = @"WATCH000001";
    detailsTitle = @"Original watch title";
    manager.titles[currentWatchID] = @"Overview and criticisms of the NYT vs. Brave case";
    [manager.toggled addObject:currentWatchID]; // A feed choice must not override the watch default.
    ASTextNode *heading = titleNode(detailsTitle);
    ASTextNode *comment = titleNode(detailsTitle);
    ASTextNode *recommendation = titleNode(detailsTitle);
    _ASCollectionViewCell *header = metadataCell(@"video_metadata.eml|3035ad7f9a19183f", @[heading]);
    _ASCollectionViewCell *commentCell = metadataCell(@"comment.eml|test", @[comment]);
    _ASCollectionViewCell *feedCell = metadataCell(@"video_with_context.eml|test", @[recommendation]);
    YTWatchNextResultsViewController *watch = [YTWatchNextResultsViewController new];
    watch.viewIfLoaded = [UIView new];
    watch.viewIfLoaded.window = YES;
    watch.collectionView = [UICollectionView new];
    watch.collectionView.visibleCells = @[commentCell, feedCell];
    [watch viewDidLoad];
    [watch collectionView:watch.collectionView willDisplayCell:header forItemAtIndexPath:nil];
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    assert([comment.attributedText.string isEqual:detailsTitle] && [recommendation.attributedText.string isEqual:detailsTitle]);
    assert(![manager isOriginalToggledForVideoID:currentWatchID]);
    watch.collectionView.visibleCells = @[header, commentCell, feedCell];
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    [watch viewDidLayoutSubviews]; // A layout pass must not undo the user's toggle.
    assert([heading.attributedText.string isEqual:detailsTitle]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:manager.titles[currentWatchID]]);
    heading.attributedText = [[NSAttributedString alloc] initWithString:detailsTitle attributes:@{NSForegroundColorAttributeName:@"new-theme"}];
    [watch viewDidLayoutSubviews];
    assert([[heading.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:@"new-theme"]);
    [manager toggleDeArrowForVideoID:currentWatchID];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    assert([[heading.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:@"new-theme"]);

    currentWatchID = @"WATCH000002";
    heading.attributedText = [[NSAttributedString alloc] initWithString:@"Next native title"];
    [watch viewDidLayoutSubviews]; // Player details still belong to the old video.
    assert([heading.attributedText.string isEqual:@"Next native title"]);
    detailsID = currentWatchID;
    detailsTitle = @"Next native title";
    header.node.nodeController.owningComponent.templateURI = @"yt://video_metadata_inner.eml|fcece9abf78ae91c";
    [[NSNotificationCenter defaultCenter] postNotificationName:@"YouModWatchStatsChanged" object:nil];
    assert([heading.attributedText.string isEqual:detailsTitle]); // No API result yet.
    manager.titles[currentWatchID] = @"Late DeArrow title";
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":@"WATCH000001"}];
    assert([heading.attributedText.string isEqual:detailsTitle]); // Ignore the previous video's response.
    [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID":currentWatchID}];
    assert([heading.attributedText.string isEqual:@"Late DeArrow title"]);
    preferences[DeArrowReplaceTitles] = NO;
    [watch viewDidLayoutSubviews];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    preferences[DeArrowReplaceTitles] = YES;
    watch.viewIfLoaded.window = NO;
    [watch viewDidLayoutSubviews];
    assert([heading.attributedText.string isEqual:detailsTitle]);
    watch.viewIfLoaded.window = YES;
    header.node.nodeController.owningComponent.templateURI = @"comment.eml|recycled";
    [watch viewDidLayoutSubviews];
    assert([heading.attributedText.string isEqual:detailsTitle]); // Reused nodes cannot brand comments.
} return 0; }
