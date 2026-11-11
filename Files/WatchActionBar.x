#import "Headers.h"

extern NSString *YouModCurrentViewCount(void);

// Match Texture's dimension/edge ABI without importing its full framework.
typedef struct { NSInteger unit; CGFloat value; } YMWatchDimension;
typedef struct {
    YMWatchDimension top, left, bottom, right, start, end, horizontal, vertical, all;
} YMWatchInsets;

@interface ASLayoutElementStyleYoga (YouModWatchRow)
@property (nonatomic) int flexWrap;
@property (nonatomic) unsigned char justifyContent;
@property (nonatomic) YMWatchDimension width;
@property (nonatomic) YMWatchDimension height;
@property (nonatomic) YMWatchDimension minWidth;
@property (nonatomic) YMWatchDimension minHeight;
@property (nonatomic) YMWatchDimension maxWidth;
@property (nonatomic) YMWatchDimension maxHeight;
@property (nonatomic) YMWatchDimension flexBasis;
@property (nonatomic) YMWatchInsets margin;
@end

static ASDisplayNode *YMFindWatchNode(ASDisplayNode *node, NSString *identifier) {
    if ([node.accessibilityIdentifier isEqualToString:identifier]) return node;
    if (node.isNodeLoaded && !node.layerBacked && [node.view.accessibilityIdentifier isEqualToString:identifier]) return node;
    for (ASDisplayNode *child in node.yogaChildren.count ? node.yogaChildren : node.subnodes) {
        ASDisplayNode *match = YMFindWatchNode(child, identifier);
        if (match) return match;
    }
    return nil;
}

static BOOL YMConfigureWatchRow(ASDisplayNode *row, BOOL wrap) {
    ASDisplayNode *layout = row;
    NSMutableArray *wrappers = [NSMutableArray arrayWithObject:row];
    while (layout.yogaChildren.count == 1) {
        ASDisplayNode *child = layout.yogaChildren.firstObject;
        if (!child.yogaChildren.count) break;
        layout = child;
        [wrappers addObject:child];
    }
    ASDisplayNode *first = nil;
    for (ASDisplayNode *child in layout.yogaChildren) {
        if (YMFindWatchNode(child, @"id.video.like.button")) { first = child; break; }
    }
    if (!first) return NO;
    ASDisplayNode *more = YMFindWatchNode(layout, @"id.ui.video.action.menu") ?: YMFindWatchNode(layout, @"id.video.action.menu") ?: YMFindWatchNode(layout, @"id.video.menu.button") ?:
        YMFindWatchNode(layout, @"eml.overflow_button") ?: YMFindWatchNode(layout, @"overflow_button");
    BOOL showToggle = IS_ENABLED(DeArrowEnabled);
    NSValue *originalMargin = objc_getAssociatedObject(more, "YMDeArrowOriginalMargin");
    BOOL moreReady = !more || (showToggle ? more.style.margin.start.value == 44 && originalMargin != nil : originalMargin == nil);
    YMWatchDimension prefix = first.style.margin.start;
    if (objc_getAssociatedObject(row, "YMWatchViewsReserved") &&
        moreReady && (!wrap || layout.style.flexWrap == 1) && prefix.unit == 1 && prefix.value == 56) return NO;
    if (more) {
        YMWatchInsets margin = more.style.margin;
        if (showToggle) {
            if (!originalMargin) {
                originalMargin = [NSValue valueWithBytes:&margin objCType:@encode(YMWatchInsets)];
                objc_setAssociatedObject(more, "YMDeArrowOriginalMargin", originalMargin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            margin.start = (YMWatchDimension){1, 44};
        } else if (originalMargin) {
            [originalMargin getValue:&margin size:sizeof(margin)];
            objc_setAssociatedObject(more, "YMDeArrowOriginalMargin", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        more.style.margin = margin;
    }
    YMWatchDimension automatic = {0, 0}, zero = {1, 0};
    // Remeasure the existing row after its views have loaded; never insert children.
    if (wrap) {
        layout.style.flexWrap = 1;
        layout.style.justifyContent = 0;
        for (ASDisplayNode *wrapper in wrappers) {
            wrapper.style.height = automatic;
            wrapper.style.maxHeight = automatic;
        }
    }
    for (ASDisplayNode *child in layout.yogaChildren) {
        if (wrap) child.style.flexGrow = 0;
        if (YMFindWatchNode(child, @"id.ui.channel.subscribe")) {
            child.style.width = automatic;
            child.style.flexBasis = automatic;
        }
        if (YMFindWatchNode(child, @"id.video.like.button")) {
            YMWatchInsets margin = child.style.margin;
            margin.start = (YMWatchDimension){1, 56};
            child.style.margin = margin;
            objc_setAssociatedObject(row, "YMWatchViewsReserved", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    ASDisplayNode *join = YMFindWatchNode(layout, @"id.sponsorship.sponsor.button");
    while (join && join != layout) {
        join.hidden = YES;
        join.style.width = join.style.minWidth = join.style.maxWidth = zero;
        join.style.height = join.style.minHeight = join.style.maxHeight = zero;
        join.style.margin = (YMWatchInsets){zero, zero, zero, zero, zero, zero, zero, zero, zero};
        join.style.flexGrow = 0;
        ASDisplayNode *parent = join.yogaParent;
        if (parent.yogaChildren.count != 1) break;
        join = parent;
    }
    return YES;
}

static UIView *YMFindWatchControl(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *match = YMFindWatchControl(child, identifier);
        if (match) return match;
    }
    return nil;
}

static CGRect YMWatchJoinViewsFrame(CGRect join) {
    return CGRectMake(CGRectGetMinX(join), CGRectGetMidY(join) - 22, MIN(52, join.size.width), 44);
}

UIView *YouModWatchRowForControl(UIView *like) {
    UIView *cell = like;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) {
        if ([cell isKindOfClass:%c(YTPlayerView)] || [cell isKindOfClass:%c(YTMainAppPlayerOverlayView)]) return nil;
        cell = cell.superview;
    }
    if (!cell) return nil;
    for (UIView *row = like.superview; row; row = row.superview) {
        if ([row isKindOfClass:%c(YTPlayerView)] || [row isKindOfClass:%c(YTMainAppPlayerOverlayView)]) return nil;
        NSString *identifier = row.accessibilityIdentifier;
        if ([identifier isEqualToString:@"id.video.non_scrollable_action_bar"] ||
            [identifier isEqualToString:@"id.video.scrollable_action_bar"]) return row;
        if ([row isKindOfClass:UICollectionViewCell.class] || [row isKindOfClass:UIScrollView.class]) break;
    }
    UIView *actions = nil;
    for (UIView *row = like.superview; row; row = row.superview) {
        if ([row isKindOfClass:UICollectionViewCell.class] || [row isKindOfClass:UIScrollView.class] ||
            [row isKindOfClass:%c(YTPlayerView)] || [row isKindOfClass:%c(YTMainAppPlayerOverlayView)] ||
            row.bounds.size.height > 100) break;
        if (!YMFindWatchControl(row, @"id.video.dislike.button") ||
            !YMFindWatchControl(row, @"id.video.share.button")) continue;
        if (!actions) actions = row;
        UIView *subscribe = YMFindWatchControl(row, @"id.ui.channel.subscribe");
        if (subscribe) {
            CGRect sub = [subscribe convertRect:subscribe.bounds toView:row];
            CGRect vote = [like convertRect:like.bounds toView:row];
            if (fabs(CGRectGetMidY(sub) - CGRectGetMidY(vote)) < 20) return row;
        }
    }
    return actions;
}

static CGRect YMWatchReservedViewsFrame(CGRect like, BOOL rightToLeft) {
    CGFloat x = rightToLeft ? CGRectGetMaxX(like) + 4 : CGRectGetMinX(like) - 56;
    return CGRectMake(x, CGRectGetMidY(like) - 22, 52, 44);
}

static CGRect YMWatchPrefixFrame(CGRect like) {
    CGFloat height = MIN(44, like.size.height);
    return CGRectMake(CGRectGetMinX(like), CGRectGetMidY(like) - height / 2, 52, height);
}

// Tablet actions are separate from the channel/Subscribe row. Reserve a prefix
// in that row instead of requiring a subscription control that is elsewhere.
static CGRect YMPrependWatchViews(UIView *bar, UIView *like) {
    UIView *first = like;
    while (first.superview && first.superview != bar) first = first.superview;
    CGRect frame = [first convertRect:first.bounds toView:bar];
    NSMutableArray *shifted = [NSMutableArray array];
    CGFloat right = 0;
    for (UIView *view in bar.subviews) {
        if ([view.accessibilityIdentifier hasPrefix:@"youmod."]) continue;
        CGRect child = [view convertRect:view.bounds toView:bar];
        if (CGRectGetMinX(child) < CGRectGetMinX(frame) - 1) continue;
        objc_setAssociatedObject(view, "YMOriginalTransform", [NSValue valueWithCGAffineTransform:view.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.transform = CGAffineTransformTranslate(view.transform, 56, 0);
        [shifted addObject:view];
        right = MAX(right, CGRectGetMaxX(child) + 56);
    }
    objc_setAssociatedObject(bar, "YMShiftedActions", shifted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([bar isKindOfClass:UIScrollView.class]) {
        UIScrollView *scroll = (UIScrollView *)bar;
        scroll.contentSize = CGSizeMake(MAX(right, bar.bounds.size.width), scroll.contentSize.height);
    }
    return YMWatchPrefixFrame(frame);
}

static void YMUpdateWatchBar(UIView *bar) {
    if (!bar.window) return;
    for (UIView *view in objc_getAssociatedObject(bar, "YMShiftedActions")) {
        NSValue *value = objc_getAssociatedObject(view, "YMOriginalTransform");
        if (value) view.transform = value.CGAffineTransformValue;
    }
    objc_setAssociatedObject(bar, "YMShiftedActions", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *like = YMFindWatchControl(bar, @"id.video.like.button");
    UIView *subscribe = YMFindWatchControl(bar, @"id.ui.channel.subscribe");
    UIView *join = YMFindWatchControl(bar, @"id.sponsorship.sponsor.button");
    UILabel *count = objc_getAssociatedObject(bar, "YMViewCount");
    if (!like) {
        count.hidden = YES;
        return;
    }
    CGRect joinFrame = join ? [join convertRect:join.bounds toView:bar] : CGRectZero;
    CGRect likeFrame = [like convertRect:like.bounds toView:bar];
    if (join) join.hidden = YES;
    ASDisplayNode *node = [bar isKindOfClass:%c(_ASDisplayView)] ? ((_ASDisplayView *)bar).keepalive_node : nil;
    if (node && !objc_getAssociatedObject(bar, "YMWatchLayoutQueued")) {
        BOOL wrap = ![bar.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"] &&
                    ![bar isKindOfClass:UIScrollView.class];
        objc_setAssociatedObject(bar, "YMWatchLayoutQueued", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakBar = bar;
        __weak ASDisplayNode *weakNode = node;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *currentBar = weakBar;
            ASDisplayNode *currentNode = weakNode;
            if (!currentBar) return;
            objc_setAssociatedObject(currentBar, "YMWatchLayoutQueued", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!currentBar.window || currentNode != ((_ASDisplayView *)currentBar).keepalive_node) return;
            if (YMConfigureWatchRow(currentNode, wrap)) [currentNode setNeedsLayout];
        });
    }
    CGRect frame;
    if (objc_getAssociatedObject(node, "YMWatchViewsReserved")) {
        BOOL rtl = bar.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
        frame = YMWatchReservedViewsFrame(likeFrame, rtl);
    } else if (!subscribe) {
        frame = YMPrependWatchViews(bar, like);
    } else {
        frame = YMWatchJoinViewsFrame(joinFrame);
    }
    if (!count) {
        count = [[UILabel alloc] init];
        count.accessibilityIdentifier = @"youmod.video.viewcount";
        count.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        count.textAlignment = NSTextAlignmentCenter;
        count.numberOfLines = 2;
        count.adjustsFontSizeToFitWidth = YES;
        count.minimumScaleFactor = 0.75;
        count.userInteractionEnabled = NO;
        objc_setAssociatedObject(bar, "YMViewCount", count, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar addSubview:count];
    }
    NSString *views = YouModCurrentViewCount();
    NSString *text = [NSString stringWithFormat:@"%@\nviews", views ?: @"—"];
    if (![count.text isEqualToString:text]) count.text = text;
    count.accessibilityLabel = [NSString stringWithFormat:@"%@ views", views ?: @"Unavailable"];
    count.textColor = UIColor.labelColor;
    if (!CGRectEqualToRect(count.frame, frame)) count.frame = frame;
    count.hidden = frame.size.width < 24;
}

static void YMMarkWatchRow(UIView *row) {
    if (!row || objc_getAssociatedObject(row, "YMWatchRow")) return;
    objc_setAssociatedObject(row, "YMWatchRow", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.sponsorship.sponsor.button"]) self.hidden = YES;
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"YouModWatchStatsChanged" object:nil];
        if (!self.window) return;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_refreshWatchBar:) name:@"YouModWatchStatsChanged" object:nil];
        // The row's other children may not be attached until this turn finishes.
        __weak UIView *weakControl = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *control = weakControl;
            if (!control.window) return;
            UIView *row = YouModWatchRowForControl(control);
            YMMarkWatchRow(row);
            YMUpdateWatchBar(row);
        });
    }
}
- (void)layoutSubviews {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.sponsorship.sponsor.button"]) self.hidden = YES;
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) {
        UIView *row = YouModWatchRowForControl(self);
        YMMarkWatchRow(row);
        YMUpdateWatchBar(row);
    } else if (objc_getAssociatedObject(self, "YMWatchRow")) {
        YMUpdateWatchBar(self);
    }
}
%new
- (void)youmod_refreshWatchBar:(NSNotification *)notification {
    YMUpdateWatchBar(YouModWatchRowForControl(self));
}
%end
