#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#define LOC(key) (key)
#define TabOrder @"YouModTabOrder"
static NSUserDefaults *preferences;

@interface YTIBrowseRequest : NSObject
/* BROWSE_DECLARATIONS */
@end
@implementation YTIBrowseRequest
/* BROWSE_METHODS */
@end
@interface YTIPivotBarItemRenderer : NSObject
@property(copy) NSString *pivotIdentifier;
@end
@implementation YTIPivotBarItemRenderer
@end
@interface YTIPivotBarSupportedRenderers : NSObject
@property(strong) YTIPivotBarItemRenderer *pivotBarItemRenderer;
@property(strong) YTIPivotBarItemRenderer *pivotBarIconOnlyItemRenderer;
@end
@implementation YTIPivotBarSupportedRenderers
@end
@interface YTIPivotBarRenderer : NSObject
@property(strong) NSMutableArray *rawItems;
@property(readonly) NSMutableArray *itemsArray;
@property(readonly) NSUInteger itemsArray_Count;
+ (YTIPivotBarSupportedRenderers *)pivotSupportedRenderersWithBrowseId:(NSString *)browseId title:(NSString *)title iconType:(NSInteger)type;
@end
/* MAPPINGS */
@implementation YTIPivotBarRenderer
+ (YTIPivotBarSupportedRenderers *)pivotSupportedRenderersWithBrowseId:(NSString *)browseId title:(NSString *)title iconType:(NSInteger)type {
    YTIPivotBarSupportedRenderers *item = [YTIPivotBarSupportedRenderers new];
    item.pivotBarItemRenderer = [YTIPivotBarItemRenderer new];
    item.pivotBarItemRenderer.pivotIdentifier = browseId;
    return item;
}
/* GETTERS */
@end

/* NODE_TYPES */
@implementation ASLayoutElementStyleYoga
@end
@interface UIView : NSObject
@property(copy) NSString *accessibilityIdentifier;
@end
@implementation UIView
@end
@interface ASDisplayNode : NSObject
@property(copy) NSString *accessibilityIdentifier;
@property(strong) ASLayoutElementStyleYoga *style;
@property(copy) NSArray *yogaChildren;
@property(copy) NSArray *subnodes;
@property(weak) ASDisplayNode *yogaParent;
@property BOOL isNodeLoaded;
@property BOOL hidden;
@property(strong) UIView *view;
@end
@implementation ASDisplayNode
- (instancetype)init {
    if ((self = [super init])) self.style = [ASLayoutElementStyleYoga new];
    return self;
}
@end
/* NODE_HELPERS */

static YTIPivotBarSupportedRenderers *tab(NSString *identifier) {
    return [YTIPivotBarRenderer pivotSupportedRenderersWithBrowseId:identifier title:identifier iconType:0];
}
static NSDictionary *entry(NSString *identifier, BOOL enabled) { return @{ @"id": identifier, @"enabled": @(enabled) }; }
static NSArray *identifiers(NSArray *items) {
    NSMutableArray *result = [NSMutableArray new];
    for (YTIPivotBarSupportedRenderers *item in items) [result addObject:item.pivotBarItemRenderer.pivotIdentifier];
    return result;
}
static ASDisplayNode *node(NSString *identifier, NSArray *children) {
    ASDisplayNode *result = [ASDisplayNode new];
    result.accessibilityIdentifier = identifier;
    result.yogaChildren = children;
    for (ASDisplayNode *child in children) child.yogaParent = result;
    return result;
}
int main(void) { @autoreleasepool {
    NSString *suite = [@"YouMod.Tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    preferences = [[NSUserDefaults alloc] initWithSuiteName:suite];
    YTIPivotBarRenderer *renderer = [YTIPivotBarRenderer new];
    renderer.rawItems = [@[tab(@"FEwhat_to_watch"), tab(@"FEshorts"), tab(@"FEuploads"), tab(@"FEsubscriptions"), tab(@"FElibrary")] mutableCopy];
    NSMutableArray *nativeArray = renderer.rawItems;
    id nativeShorts = nativeArray[1];
    assert(renderer.itemsArray == nativeArray && renderer.itemsArray_Count == 5);
    [preferences setObject:@[entry(@"home",YES),entry(@"shorts",NO),entry(@"create",NO),entry(@"notifications",YES),entry(@"subscriptions",YES),entry(@"library",YES)] forKey:TabOrder];
    assert(renderer.itemsArray_Count == 4); // Count can be the first read.
    assert(([identifiers(renderer.itemsArray) isEqual:@[@"FEwhat_to_watch",@"FEnotifications_inbox",@"FEsubscriptions",@"FElibrary"]]));
    assert(renderer.itemsArray == nativeArray); // Navigation shares the same array.
    id notification = renderer.itemsArray[1];
    // A getter called while iterating must not mutate the enumerated array.
    for (id item in renderer.itemsArray) { (void)item; assert(renderer.itemsArray_Count == 4); }
    assert(renderer.itemsArray[1] == notification);
    [preferences setObject:@[entry(@"shorts",YES),entry(@"home",YES),entry(@"create",YES)] forKey:TabOrder];
    assert(([identifiers(renderer.itemsArray) isEqual:@[@"FEshorts",@"FEwhat_to_watch",@"FEuploads"]]));
    assert(renderer.itemsArray[0] == nativeShorts); // Re-enabling uses the original command.
    [preferences setObject:@[@"invalid",@{@"id":@42},entry(@"unknown",YES)] forKey:TabOrder];
    assert(renderer.itemsArray_Count == 3); // Invalid data must not empty navigation.
    [preferences removePersistentDomainForName:suite];

    ASDisplayNode *subscribe = node(@"id.ui.channel.subscribe",nil);
    ASDisplayNode *join = node(@"id.sponsorship.sponsor.button",nil);
    ASDisplayNode *channel = node(nil,@[subscribe,join]);
    ASDisplayNode *like = node(nil,nil); // UIKit identifier arrives after materialization.
    like.isNodeLoaded = YES;
    like.view = [UIView new];
    like.view.accessibilityIdentifier = @"id.video.like.button";
    ASDisplayNode *share = node(@"id.video.share.button",nil);
    ASDisplayNode *gemini = node(@"gemini",nil);
    ASDisplayNode *row = node(nil,@[channel,like,share,gemini]); // No renderer identifier needed.
    channel.style.flexGrow = 1;
    row.style.height = (YMWatchDimension){1,44};
    row.style.maxHeight = (YMWatchDimension){1,44};
    assert(YMConfigureWatchRow(row,YES));
    assert(row.style.flexWrap == 1 && row.style.height.unit == 0 && row.style.maxHeight.unit == 0);
    assert(channel.style.flexGrow == 0 && like.style.margin.start.value == 56);
    assert(join.hidden && join.style.maxWidth.value == 0 && !subscribe.hidden && !channel.hidden);
    assert(row.yogaChildren.count == 4 && channel.yogaChildren.count == 2 && !gemini.hidden);
    assert(!YMConfigureWatchRow(row,YES)); // No repeated remeasurement loop.
    row.style.flexWrap = 0; // Native renderer refresh overwrites its style.
    assert(YMConfigureWatchRow(row,YES) && row.style.flexWrap == 1);
    ASDisplayNode *tablet = node(nil,@[node(@"id.video.like.button",nil),share]);
    tablet.style.height = (YMWatchDimension){1,32};
    assert(YMConfigureWatchRow(tablet,NO) && tablet.style.flexWrap == 0 && tablet.style.height.value == 32);
    assert(!YMConfigureWatchRow(node(nil,@[share]),YES));
    ASDisplayNode *inner = node(nil,@[node(@"id.video.like.button",nil),node(@"gemini",nil)]);
    ASDisplayNode *outer = node(nil,@[inner]);
    outer.style.height = (YMWatchDimension){1,44};
    assert(YMConfigureWatchRow(outer,YES) && inner.style.flexWrap == 1 && outer.style.height.unit == 0);
    assert(objc_getAssociatedObject(outer, "YMWatchViewsReserved"));
    assert(!YMConfigureWatchRow(outer,YES));
} return 0; }
