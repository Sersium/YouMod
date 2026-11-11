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
@interface ASDisplayNode : NSObject
@property BOOL isNodeLoaded;
@property BOOL layerBacked;
@property(strong) ASDisplayNode *supernode;
@property(strong) UIView *view;
@property CGRect bounds;
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node;
@end
@implementation ASDisplayNode
- (UIView *)view { assert(!self.layerBacked); return _view; }
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node { return rect; }
@end
@interface ASTextNode : ASDisplayNode
@property(copy) NSArray *exclusionPaths;
@property NSUInteger assignments;
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
- (void)registerOriginalTitle:(NSString *)title forVideoID:(NSString *)videoID { self.originals[videoID] = title; }
- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID { return [self.toggled containsObject:videoID]; }
- (NSString *)titleForVideoID:(NSString *)videoID { return self.titles[videoID]; }
- (NSString *)originalTitleForVideoID:(NSString *)videoID { return self.originals[videoID]; }
- (void)prefetchBrandingForVideoID:(NSString *)videoID {}
@end
static void YouModCollectNodesFromView(NSArray *labels, NSMutableArray *texts, NSMutableArray *images) {
    [texts addObjectsFromArray:labels];
}
/* WATCH_BINDING */

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
    // Late network completion updates both the legacy and Elements title.
    YouModUpdateWatchTitle(cell);
    assert(cell.titleLabel.attributedText == native);
    manager.titles[firstID] = @"DeArrow title";
    YouModUpdateWatchTitle(cell);
    assert([cell.titleLabel.attributedText.string isEqual:@"DeArrow title"]);
    assert([experimental.attributedText.string isEqual:@"DeArrow title"]);
    cell.experimentalTitleLabel = experimental; // Current YouTube uses a YTLabel.
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
} return 0; }
