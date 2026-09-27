#import "Headers.h"

extern NSString *YouModCurrentViewCount(void);

// Keep native command handlers weak: proxies must not keep recycled cards alive.
%hook ELMTouchCommandPropertiesHandler
- (id)handlePropertyForRecognizer:(id)recognizer hasTouchCommand:(BOOL)hasCommand handler:(SEL)action recognizerClass:(Class)recognizerClass {
    UIGestureRecognizer *result = %orig;
    if (action == @selector(handleTap) && result) {
        NSHashTable *target = [NSHashTable weakObjectsHashTable];
        [target addObject:self];
        objc_setAssociatedObject(result, "YMNativeTapTarget", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return result;
}
%end

static UIView *YMFindWatchControl(UIView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (UIView *child in view.subviews) {
        UIView *match = YMFindWatchControl(child, identifier);
        if (match) return match;
    }
    return nil;
}

static id YMWatchTapTarget(UIView *view) {
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        id target = [objc_getAssociatedObject(recognizer, "YMNativeTapTarget") anyObject];
        if (target) return target;
    }
    for (UIView *child in view.subviews) {
        id target = YMWatchTapTarget(child);
        if (target) return target;
    }
    return nil;
}

static UIView *YMFindWatchAuxiliary(UIView *view, BOOL gemini) {
    NSString *identifier = view.accessibilityIdentifier.lowercaseString ?: @"";
    NSString *label = view.accessibilityLabel.lowercaseString ?: @"";
    if (![identifier hasPrefix:@"youmod."]) {
        BOOL match = gemini ? ([identifier containsString:@"gemini"] || [identifier containsString:@"ask"] ||
                              [label isEqualToString:@"ask"] || [label containsString:@"ask youtube"] || [label containsString:@"gemini"])
                           : ([identifier containsString:@"overflow"] || [identifier containsString:@"action.menu"] ||
                              [label isEqualToString:@"more actions"] || [label isEqualToString:@"action menu"]);
        if (match) return view;
        for (UIView *child in view.subviews) {
            UIView *match = YMFindWatchAuxiliary(child, gemini);
            if (match) return match;
        }
    }
    return nil;
}

static void YMRestoreWatchActions(UIView *bar) {
    for (UIView *view in objc_getAssociatedObject(bar, "YMShiftedActions")) {
        NSValue *value = objc_getAssociatedObject(view, "YMOriginalTransform");
        if (value) view.transform = value.CGAffineTransformValue;
    }
    objc_setAssociatedObject(bar, "YMShiftedActions", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *gemini = objc_getAssociatedObject(bar, "YMMovedGemini");
    UIView *more = objc_getAssociatedObject(bar, "YMMovedMore");
    gemini.hidden = NO;
    more.hidden = NO;
    ((UIView *)objc_getAssociatedObject(bar, "YMGeminiOverflow")).hidden = YES;
    objc_setAssociatedObject(bar, "YMMovedGemini", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, "YMMovedMore", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Only on a crowded row: move Gemini to the existing three-dot position and
// forward both Gemini and the original More actions to their native handlers.
static CGRect YMFreeGeminiSlot(UIView *bar, UIView *like) {
    UIView *gemini = YMFindWatchAuxiliary(bar, YES);
    UIView *more = YMFindWatchAuxiliary(bar, NO);
    id geminiTarget = gemini ? YMWatchTapTarget(gemini) : nil;
    id moreTarget = more ? YMWatchTapTarget(more) : nil;
    if (!geminiTarget || !moreTarget || gemini.hidden || more.hidden) return CGRectZero;
    CGRect first = [like convertRect:like.bounds toView:bar];
    CGRect last = [gemini convertRect:gemini.bounds toView:bar];
    CGFloat slot = MIN(44, last.size.width);
    if (slot < 28 || last.origin.x <= first.origin.x) return CGRectZero;
    NSMutableArray *shifted = [NSMutableArray array];
    for (NSString *identifier in @[@"id.video.like.button", @"id.video.dislike.button", @"id.video.share.button"]) {
        UIView *view = YMFindWatchControl(bar, identifier);
        if (!view) continue;
        // Include the native count layer's parent when the icon is a small leaf.
        if (view.bounds.size.height < 36 && view.superview != bar && view.superview.subviews.count == 1) view = view.superview;
        CGRect frame = [view convertRect:view.bounds toView:bar];
        if (CGRectGetMaxX(frame) + slot > CGRectGetMaxX(last) + 1) return CGRectZero;
        [shifted addObject:view];
    }
    for (UIView *view in shifted) {
        objc_setAssociatedObject(view, "YMOriginalTransform", [NSValue valueWithCGAffineTransform:view.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        view.transform = CGAffineTransformTranslate(view.transform, slot, 0);
    }
    objc_setAssociatedObject(bar, "YMShiftedActions", shifted, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIButton *overflow = objc_getAssociatedObject(bar, "YMGeminiOverflow");
    if (!overflow) {
        overflow = [UIButton buttonWithType:UIButtonTypeSystem];
        overflow.accessibilityIdentifier = @"youmod.watch.overflow";
        overflow.accessibilityLabel = @"More actions";
        [overflow setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        overflow.showsMenuAsPrimaryAction = YES;
        objc_setAssociatedObject(bar, "YMGeminiOverflow", overflow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bar addSubview:overflow];
    }
    __weak id weakGemini = geminiTarget, weakMore = moreTarget;
    overflow.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:gemini.accessibilityLabel ?: @"Ask Gemini" image:[UIImage systemImageNamed:@"sparkles"] identifier:nil handler:^(__kindof UIAction *action) { [weakGemini handleTap]; }],
        [UIAction actionWithTitle:@"More actions…" image:[UIImage systemImageNamed:@"ellipsis"] identifier:nil handler:^(__kindof UIAction *action) { [weakMore handleTap]; }]
    ]];
    overflow.frame = [more convertRect:more.bounds toView:bar];
    overflow.tintColor = UIColor.labelColor;
    overflow.hidden = NO;
    gemini.hidden = YES;
    more.hidden = YES;
    objc_setAssociatedObject(bar, "YMMovedGemini", gemini, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, "YMMovedMore", more, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return CGRectMake(first.origin.x, CGRectGetMidY(first) - 22, slot - 4, 44);
}

// Reuse the space already allocated to Join/Subscribe. Native vote, share,
// Gemini and overflow controls keep their frames and their normal tap behavior.
static CGRect YMWatchViewCountFrame(CGRect subscribe, CGRect join, CGRect like, BOOL compact) {
    CGFloat start = CGRectIsEmpty(join) ? CGRectGetMinX(subscribe) : MIN(CGRectGetMinX(join), CGRectGetMinX(subscribe));
    CGFloat x = compact ? start + 44 + 4 : start;
    CGFloat right = compact ? CGRectGetMinX(like) - 4 : CGRectGetMaxX(join);
    return CGRectMake(x, CGRectGetMidY(subscribe) - 22, MAX(0, right - x), 44);
}

// Discover the actual row from a vote control. The compact phone row and
// tablet scrollable row do not share an accessibility identifier.
static UIView *YMWatchRowForControl(UIView *like) {
    UIView *actions = nil;
    for (UIView *row = like.superview; row; row = row.superview) {
        if (row.bounds.size.height > 100) break;
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
    YMRestoreWatchActions(bar);
    UIView *like = YMFindWatchControl(bar, @"id.video.like.button");
    UIView *subscribe = YMFindWatchControl(bar, @"id.ui.channel.subscribe");
    UIView *join = YMFindWatchControl(bar, @"id.sponsorship.sponsor.button");
    UILabel *count = objc_getAssociatedObject(bar, "YMViewCount");
    UIButton *compact = objc_getAssociatedObject(bar, "YMCompactSubscribe");
    if (!like) {
        count.hidden = YES;
        compact.hidden = YES;
        return;
    }
    CGRect subFrame = subscribe ? [subscribe convertRect:subscribe.bounds toView:bar] : CGRectZero;
    CGRect joinFrame = join ? [join convertRect:join.bounds toView:bar] : CGRectZero;
    CGRect likeFrame = [like convertRect:like.bounds toView:bar];
    id target = YMWatchTapTarget(subscribe);
    // Some Elements buttons attach the recognizer to a single-child wrapper.
    if (!target && subscribe.superview != bar && subscribe.superview.subviews.count == 1)
        target = YMWatchTapTarget(subscribe.superview);
    if (join) join.hidden = YES;
    CGRect frame = YMWatchViewCountFrame(subFrame, joinFrame, likeFrame, target != nil);
    CGFloat subscribeX = frame.origin.x - 48;
    if (!subscribe && CGRectIsEmpty(frame)) frame = YMPrependWatchViews(bar, like);
    else if (frame.size.width < 24) frame = YMFreeGeminiSlot(bar, like);
    if (target && frame.size.width >= 24) {
        if (!compact) {
            compact = [UIButton buttonWithType:UIButtonTypeSystem];
            compact.accessibilityIdentifier = @"youmod.compact.subscribe";
            compact.layer.cornerRadius = 22;
            objc_setAssociatedObject(bar, "YMCompactSubscribe", compact, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [bar addSubview:compact];
        }
        [compact removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
        [compact addTarget:target action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
        // Use the native label/traits, including the current subscription state.
        compact.accessibilityLabel = subscribe.accessibilityLabel ?: @"Subscribe or notification options";
        compact.accessibilityTraits = subscribe.accessibilityTraits | UIAccessibilityTraitButton;
        static UIImage *icon;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ icon = [UIImage systemImageNamed:@"bell"]; });
        if ([compact imageForState:UIControlStateNormal] != icon) [compact setImage:icon forState:UIControlStateNormal];
        compact.tintColor = UIColor.labelColor;
        compact.backgroundColor = UIColor.secondarySystemBackgroundColor;
        CGRect compactFrame = CGRectMake(subscribeX, CGRectGetMidY(subFrame) - 22, 44, 44);
        if (!CGRectEqualToRect(compact.frame, compactFrame)) compact.frame = compactFrame;
        compact.hidden = NO;
        subscribe.hidden = YES;
    } else {
        // Never replace a subscription control unless its original action is available.
        compact.hidden = YES;
        subscribe.hidden = NO;
        if (CGRectIsEmpty(frame) && subscribe) frame = YMWatchViewCountFrame(subFrame, joinFrame, likeFrame, NO);
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
        if (self.window) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_refreshWatchBar:) name:@"YouModWatchStatsChanged" object:nil];
        // The row's other children may not be attached until this turn finishes.
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *row = YMWatchRowForControl(self);
            YMMarkWatchRow(row);
            YMUpdateWatchBar(row);
        });
    }
}
- (void)layoutSubviews {
    %orig;
    if ([self.accessibilityIdentifier isEqualToString:@"id.sponsorship.sponsor.button"]) self.hidden = YES;
    if ([self.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) {
        UIView *row = YMWatchRowForControl(self);
        YMMarkWatchRow(row);
        YMUpdateWatchBar(row);
    } else if (objc_getAssociatedObject(self, "YMWatchRow")) {
        YMUpdateWatchBar(self);
    }
}
%new
- (void)youmod_refreshWatchBar:(NSNotification *)notification {
    YMUpdateWatchBar(YMWatchRowForControl(self));
}
%end
