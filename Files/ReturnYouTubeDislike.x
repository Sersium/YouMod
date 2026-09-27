#import "Headers.h"

// Return YouTube Dislike (RYD) Integration for YouMod
// API: https://returnyoutubedislikeapi.com/votes?videoId={videoId}

static NSString * const kYMReturnDislikeNotification = @"YouModReturnDislikeNotification";
static __weak YTPlayerViewController *currentWatchPlayer = nil;

static NSString *YouModFormatVoteCount(NSInteger count) {
    if (count < 0) return @"0";
    if (count < 1000) return [NSString stringWithFormat:@"%ld", (long)count];
    if (count < 1000000) {
        double k = count / 1000.0;
        return (k >= 10.0) ? [NSString stringWithFormat:@"%.0fK", k] : [NSString stringWithFormat:@"%.1fK", k];
    }
    double m = count / 1000000.0;
    return (m >= 10.0) ? [NSString stringWithFormat:@"%.0fM", m] : [NSString stringWithFormat:@"%.1fM", m];
}

@interface YouModRYDManager : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *votesCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
@property (nonatomic, strong) NSCache<NSString *, NSDate *> *requestDates;
+ (instancetype)sharedInstance;
- (void)fetchVotesForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *votes))completion;
- (NSDictionary *)cachedVotesForVideoID:(NSString *)videoID;
@end

@implementation YouModRYDManager

+ (instancetype)sharedInstance {
    static YouModRYDManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YouModRYDManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _votesCache = [[NSCache alloc] init];
        _votesCache.countLimit = 200;
        _inFlightRequests = [NSMutableSet set];
        _requestDates = [[NSCache alloc] init];
        _requestDates.countLimit = 200;
    }
    return self;
}

- (NSDictionary *)cachedVotesForVideoID:(NSString *)videoID {
    if (!videoID) return nil;
    return [_votesCache objectForKey:videoID];
}

- (void)fetchVotesForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *votes))completion {
    if (!videoID || videoID.length == 0) {
        if (completion) completion(nil);
        return;
    }

    NSDictionary *cached = [_votesCache objectForKey:videoID];
    if (cached) {
        if (completion) completion(cached);
        return;
    }

    @synchronized (_inFlightRequests) {
        NSDate *lastRequest = [_requestDates objectForKey:videoID];
        if ([_inFlightRequests containsObject:videoID] || (lastRequest && -lastRequest.timeIntervalSinceNow < 60)) {
            if (completion) completion(nil);
            return;
        }
        [_inFlightRequests addObject:videoID];
        [_requestDates setObject:[NSDate date] forKey:videoID];
    }

    NSString *urlString = [NSString stringWithFormat:@"https://returnyoutubedislikeapi.com/votes?videoId=%@", videoID];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        @synchronized (_inFlightRequests) {
            [_inFlightRequests removeObject:videoID];
        }
        if (completion) completion(nil);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 5.0;
    request.cachePolicy = NSURLRequestReturnCacheDataElseLoad;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        @synchronized (self.inFlightRequests) {
            [self.inFlightRequests removeObject:videoID];
        }

        if (error || !data) {
            if (completion) completion(nil);
            return;
        }

        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        if (httpResp.statusCode != 200) {
            if (completion) completion(nil);
            return;
        }

        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) {
            if (completion) completion(nil);
            return;
        }

        NSDictionary *voteData = (NSDictionary *)json;
        if (![voteData[@"likes"] isKindOfClass:[NSNumber class]] || ![voteData[@"dislikes"] isKindOfClass:[NSNumber class]]) {
            if (completion) completion(nil);
            return;
        }
        [self.votesCache setObject:voteData forKey:videoID];

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([currentWatchPlayer.contentVideoID isEqualToString:videoID]) [[NSNotificationCenter defaultCenter] postNotificationName:@"YouModWatchStatsChanged" object:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:kYMReturnDislikeNotification object:nil userInfo:@{@"videoID": videoID, @"votes": voteData}];
            if (completion) completion(voteData);
        });
    }];
    [task resume];
}

@end

#pragma mark - Declarations for Elements & Texture Nodes

@interface ELMNodeController (RYD)
- (id)owningComponent;
@end

@interface ELMCellNode (RYD)
- (ELMNodeController *)controller;
@end

@interface ELMContainerNode (RYD)
@end

@interface ELMTextNode (RYD)
@property (nonatomic, copy) NSAttributedString *attributedText;
- (id)element;
@end

#pragma mark - Hooks

static NSString *YouModGetCurrentVideoID(void) {
    return currentWatchPlayer.contentVideoID;
}

// Prefer the watched video's native metadata; the existing RYD response is a
// fallback and requires no additional request.
NSString *YouModCurrentViewCount(void) {
    YTIVideoDetails *details = currentWatchPlayer.activeVideo.singleVideo.playbackData.playerResponse.playerData.videoDetails;
    NSString *videoID = YouModGetCurrentVideoID();
    NSString *value = [details.videoId isEqualToString:videoID] ? details.viewCount : nil;
    long long views = 0;
    if (value.length && [[NSScanner scannerWithString:value] scanLongLong:&views] && views >= 0)
        return YouModFormatVoteCount(views);
    id cached = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoID][@"viewCount"];
    return [cached isKindOfClass:NSNumber.class] ? YouModFormatVoteCount([cached longLongValue]) : nil;
}

// These lifecycle selectors are present in YouTube 21.38.2. The old
// setPlayerResponse:/loadVideoWithPlaybackData: hooks are no longer called.
static void YouModWatchVideoChanged(YTPlayerViewController *player) {
    if (player.isInlinePlaybackActive || [player.activeVideoPlayerOverlay isKindOfClass:%c(YTInlineMutedPlaybackPlayerOverlayViewController)]) return;
    NSString *videoID = player.contentVideoID;
    if (!videoID.length) return;
    currentWatchPlayer = player;
    if (IS_ENABLED(ReturnYouTubeDislike)) [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoID completion:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"YouModWatchStatsChanged" object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kYMReturnDislikeNotification object:nil userInfo:@{@"videoID": videoID}];
    });
}

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    YouModWatchVideoChanged(self);
}
- (void)playbackController:(id)controller didActivateNewPlaybackWithContentVideo:(id)video {
    %orig;
    YouModWatchVideoChanged(self);
}
%end

@interface ASDisplayNode (YouModVoteLayer)
- (CALayer *)layer;
@property (nonatomic) UIAccessibilityTraits accessibilityTraits;
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node;
@end

static BOOL YouModIsVoteButton(ASDisplayNode *node) {
    return [node.accessibilityIdentifier isEqualToString:@"id.video.like.button"] ||
           [node.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"];
}

static ASDisplayNode *YMFindVoteNode(ASDisplayNode *node, NSString *identifier) {
    if ([node.accessibilityIdentifier isEqualToString:identifier]) return node;
    for (ASDisplayNode *child in node.subnodes) {
        ASDisplayNode *found = YMFindVoteNode(child, identifier);
        if (found) return found;
    }
    return nil;
}

// A shared tablet pill has room beside the icons, not underneath its existing
// title. Paint an owned, non-interactive surface over it; native hit targets,
// gestures and accessibility remain in place underneath.
static BOOL YMUpdateVotePill(ASDisplayNode *parent, NSDictionary *votes, BOOL visible) {
    ASDisplayNode *like = nil, *dislike = nil;
    for (ASDisplayNode *candidate = parent; candidate; candidate = candidate.yogaParent ?: candidate.supernode) {
        if (candidate.bounds.size.width > 200 || candidate.bounds.size.height > 48) break;
        like = YMFindVoteNode(candidate, @"id.video.like.button");
        dislike = YMFindVoteNode(candidate, @"id.video.dislike.button");
        if (like && dislike) { parent = candidate; break; }
    }
    CALayer *surface = objc_getAssociatedObject(parent, "YMVotePill");
    if (!like || !dislike || !parent.isNodeLoaded || parent.bounds.size.width < 64 || parent.bounds.size.height < 28 ||
        YMFindVoteNode(parent, @"id.video.share.button") || YMFindVoteNode(parent, @"id.ui.channel.subscribe")) {
        [surface removeFromSuperlayer];
        return NO;
    }
    if (!visible || !IS_ENABLED(ReturnYouTubeDislike)) {
        [surface removeFromSuperlayer];
        return YES;
    }
    if (!surface) {
        surface = [CALayer layer];
        surface.actions = @{ @"bounds": NSNull.null, @"position": NSNull.null, @"contents": NSNull.null };
        surface.zPosition = 1;
        surface.contentsScale = UIScreen.mainScreen.scale;
        objc_setAssociatedObject(parent, "YMVotePill", surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL dark = isDarkMode([parent closestViewController].viewIfLoaded);
    BOOL liked = (like.accessibilityTraits & UIAccessibilityTraitSelected) != 0;
    BOOL disliked = (dislike.accessibilityTraits & UIAccessibilityTraitSelected) != 0;
    CGRect left = [like convertRect:like.bounds toNode:parent];
    CGRect right = [dislike convertRect:dislike.bounds toNode:parent];
    CGFloat split = (CGRectGetMidX(left) + CGRectGetMidX(right)) / 2;
    NSString *likes = IS_ENABLED(RYDShowLikes) ? (votes ? YouModFormatVoteCount([votes[@"likes"] integerValue]) : @"—") : @"";
    NSString *dislikes = IS_ENABLED(RYDShowDislikes) ? (votes ? YouModFormatVoteCount([votes[@"dislikes"] integerValue]) : @"—") : @"";
    NSString *key = [NSString stringWithFormat:@"%@/%@/%d/%d/%d/%@/%.1f", likes, dislikes, liked, disliked, dark, NSStringFromCGRect(parent.bounds), split];
    if (![key isEqual:objc_getAssociatedObject(parent, "YMVotePillDrawing")]) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:parent.bounds.size];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            UIColor *ink = dark ? UIColor.whiteColor : UIColor.blackColor;
            [(dark ? [UIColor colorWithWhite:0.14 alpha:1] : [UIColor colorWithWhite:0.94 alpha:1]) setFill];
            UIRectFill(CGRectMake(0, 0, parent.bounds.size.width, parent.bounds.size.height));
            NSArray *names = @[liked ? @"hand.thumbsup.fill" : @"hand.thumbsup", disliked ? @"hand.thumbsdown.fill" : @"hand.thumbsdown"];
            NSArray *values = @[likes, dislikes];
            for (NSUInteger i = 0; i < 2; i++) {
                CGFloat start = i ? split : 0, end = i ? parent.bounds.size.width : split;
                CGFloat center = (start + end) / 2;
                UIImage *icon = [[UIImage systemImageNamed:names[i]] imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
                [icon drawInRect:CGRectMake(center - 9, 1, 18, 18)];
                NSString *text = values[i];
                NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:10], NSForegroundColorAttributeName: ink};
                CGSize size = [text sizeWithAttributes:attributes];
                [text drawAtPoint:CGPointMake(center - size.width / 2, parent.bounds.size.height - 12) withAttributes:attributes];
            }
        }];
        surface.contents = (__bridge id)image.CGImage;
        objc_setAssociatedObject(parent, "YMVotePillDrawing", key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    surface.frame = parent.bounds;
    surface.cornerRadius = parent.bounds.size.height / 2;
    surface.masksToBounds = YES;
    if (surface.superlayer != parent.layer) [parent.layer addSublayer:surface];
    return YES;
}

static ASTextNode *YMNativeVoteText(ASDisplayNode *node, ASDisplayNode *button, ASDisplayNode *other) {
    if ([node isKindOfClass:%c(ASTextNode)]) {
        ASTextNode *text = (ASTextNode *)node;
        if (!text.attributedText.length) return nil;
        CGRect rect = [text convertRect:text.bounds toNode:button];
        CGFloat center = CGRectGetMidX(rect);
        if (other) {
            CGFloat otherCenter = CGRectGetMidX([other convertRect:other.bounds toNode:button]);
            if (fabs(center - otherCenter) < fabs(center - CGRectGetMidX(button.bounds))) return nil;
        }
        return text;
    }
    for (ASDisplayNode *child in node.subnodes) {
        if (child == other) continue;
        ASTextNode *text = YMNativeVoteText(child, button, other);
        if (text) return text;
    }
    return nil;
}

static CGRect YMVoteLabelFrame(CGRect button, CGRect host) {
    CGFloat width = MIN(42, button.size.width);
    return CGRectMake(CGRectGetMidX(button) - width / 2,
                      MAX(CGRectGetMinY(button), CGRectGetMaxY(host) - 12), width, 12);
}

// Never add Yoga children to a native measured/automatically managed node.
// A separate text layer cannot change the native hit target or trigger relayout.
static void YouModUpdateVoteNode(ASDisplayNode *button) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ YouModUpdateVoteNode(button); });
        return;
    }
    if (!YouModIsVoteButton(button) || !button.isNodeLoaded) return;
    CATextLayer *label = objc_getAssociatedObject(button, "kYMVoteLabel");
    BOOL likes = [button.accessibilityIdentifier isEqualToString:@"id.video.like.button"];
    NSString *videoID = YouModGetCurrentVideoID();
    ASDisplayNode *parent = button.yogaParent ?: button.supernode;
    if (!IS_ENABLED(ReturnYouTubeDislike) || !videoID.length || !(button.interfaceState & 8)) {
        [label removeFromSuperlayer];
        YMUpdateVotePill(parent, nil, NO);
        return;
    }
    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoID];
    if (!votes) [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoID completion:nil];
    id number = votes[likes ? @"likes" : @"dislikes"];
    NSString *text = [number isKindOfClass:NSNumber.class] ? YouModFormatVoteCount([number integerValue]) : @"—";
    if (YMUpdateVotePill(parent, votes, YES)) {
        [label removeFromSuperlayer];
        return;
    }
    if (!(likes ? IS_ENABLED(RYDShowLikes) : IS_ENABLED(RYDShowDislikes))) {
        [label removeFromSuperlayer];
        return;
    }
    ASDisplayNode *other = YMFindVoteNode(parent, likes ? @"id.video.dislike.button" : @"id.video.like.button");
    ASTextNode *nativeText = YMNativeVoteText(button, button, other);
    if (!nativeText && parent && !other && parent.bounds.size.width <= 100 && parent.bounds.size.height <= 48)
        nativeText = YMNativeVoteText(parent, button, nil);
    if (nativeText) {
        [label removeFromSuperlayer];
        if (votes && ![nativeText.attributedText.string isEqualToString:text]) {
            NSMutableAttributedString *value = [nativeText.attributedText mutableCopy];
            [value.mutableString setString:text];
            nativeText.attributedText = value;
        }
        return;
    }
    if (!label) {
        label = [CATextLayer layer];
        label.fontSize = 10;
        label.alignmentMode = kCAAlignmentCenter;
        label.contentsScale = UIScreen.mainScreen.scale;
        objc_setAssociatedObject(button, "kYMVoteLabel", label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CALayer *host = button.layer;
    // Small icon-only nodes have a larger native parent hit target.
    if (host.bounds.size.height < 36 && button.yogaParent.isNodeLoaded) host = button.yogaParent.layer;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    label.string = text;
    label.foregroundColor = (isDarkMode([button closestViewController].viewIfLoaded) ? UIColor.whiteColor : UIColor.blackColor).CGColor;
    // The tablet's two icons may share a pill parent. Position each label
    // beneath its own icon, never at that shared parent's center.
    CGRect icon = [button.layer convertRect:button.bounds toLayer:host];
    label.frame = YMVoteLabelFrame(icon, host.bounds);
    if (label.superlayer != host) [host addSublayer:label];
    [CATransaction commit];
}

%hook ELMContainerNode
- (void)didLoad {
    %orig;
    if (!YouModIsVoteButton(self)) return;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_updateVoteCount:) name:kYMReturnDislikeNotification object:nil];
    YouModUpdateVoteNode(self);
}
- (void)didEnterVisibleState {
    %orig;
    if (YouModIsVoteButton(self)) YouModUpdateVoteNode(self);
}
- (void)didExitVisibleState {
    %orig;
    if (YouModIsVoteButton(self)) YouModUpdateVoteNode(self);
}
- (void)layoutDidFinish {
    %orig;
    if (YouModIsVoteButton(self)) YouModUpdateVoteNode(self);
}
%new
- (void)youmod_updateVoteCount:(NSNotification *)note {
    YouModUpdateVoteNode(self);
}
%end

@interface YTQTMButton (YouModVoteTitle)
- (void)youmod_updateVoteTitle:(NSNotification *)note;
@end

// Older UIKit action buttons still use their native title layout.
%hook YTQTMButton
- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMReturnDislikeNotification object:nil];
    if (!self.window) return;
    NSString *identifier = self.accessibilityIdentifier;
    if (![identifier isEqualToString:@"id.video.like.button"] && ![identifier isEqualToString:@"id.video.dislike.button"]) return;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_updateVoteTitle:) name:kYMReturnDislikeNotification object:nil];
    [self youmod_updateVoteTitle:nil];
}
%new
- (void)youmod_updateVoteTitle:(NSNotification *)note {
    if (!IS_ENABLED(ReturnYouTubeDislike)) return;
    BOOL likes = [self.accessibilityIdentifier isEqualToString:@"id.video.like.button"];
    if (!(likes ? IS_ENABLED(RYDShowLikes) : IS_ENABLED(RYDShowDislikes))) return;
    NSString *videoID = YouModGetCurrentVideoID();
    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoID];
    id number = votes[likes ? @"likes" : @"dislikes"];
    if (![number isKindOfClass:[NSNumber class]]) {
        [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoID completion:nil];
        return;
    }
    NSString *title = YouModFormatVoteCount([number integerValue]);
    [self setTitle:title forState:UIControlStateNormal];
    [self setTitle:title forState:UIControlStateSelected];
}
%end

#pragma mark - Feed metadata

extern BOOL YouModIsOverflowButtonView(UIView *view);
extern UIView *YouModVideoCard(UIView *menu, NSMutableArray *texts, NSMutableArray *images, NSString **videoID);

@interface ASTextNode (YouModFeedVotes)
@property (nonatomic) NSUInteger maximumNumberOfLines;
@end

static NSRange YMFeedViewCountRange(NSString *text) {
    if (!text.length) return NSMakeRange(NSNotFound, 0);
    static NSRegularExpression *pattern, *standalone;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        standalone = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(?:[.,][0-9]+|[ \\x{00A0}][0-9]{3})*(?:\\s*[KMBkmb])?$" options:0 error:nil];
        pattern = [NSRegularExpression regularExpressionWithPattern:@"(?:[▷▹▶\\uFFFC]\\s*[0-9]+(?:[.,][0-9]+|[ \\x{00A0}][0-9]{3})*(?:\\s*[KMBkmb])?|[0-9]+(?:[.,][0-9]+|[ \\x{00A0}][0-9]{3})*(?:\\s*[KMBkmb])?\\s+(?:views?|vues?))" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSTextCheckingResult *match = [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) match = [standalone firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    return match ? match.range : NSMakeRange(NSNotFound, 0);
}

static void YMSetFeedVoteText(ASTextNode *node, NSAttributedString *text) {
    if ([node.attributedText isEqualToAttributedString:text]) return;
    objc_setAssociatedObject(node, "YMSettingFeedVotes", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    node.attributedText = text;
    objc_setAssociatedObject(node, "YMFeedRenderedText", text.string, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(node, "YMSettingFeedVotes", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YMUpdateFeedVotes(UIView *menu) {
    if (!menu.window || !YouModIsOverflowButtonView(menu)) return;
    NSMutableArray *texts = [NSMutableArray array], *images = [NSMutableArray array];
    NSString *videoID = nil;
    if (!YouModVideoCard(menu, texts, images, &videoID) || videoID.length != 11) return;
    BOOL enabled = IS_ENABLED(ReturnYouTubeDislike) && (IS_ENABLED(RYDShowLikes) || IS_ENABLED(RYDShowDislikes));
    NSDictionary *votes = enabled ? [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoID] : nil;
    BOOL found = NO;
    for (ASTextNode *node in texts) {
        NSAttributedString *base = objc_getAssociatedObject(node, "YMFeedBaseText") ?: node.attributedText;
        if (!base.length) continue;
        // ponytail: recognize current English/French view metadata and numeric
        // labels; add renderer field mapping if other locales need support.
        UIFont *font = [base attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
        NSNumber *weight = font.fontDescriptor.fontAttributes[UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
        if (font.pointSize > 14 || weight.doubleValue >= UIFontWeightMedium) continue;
        NSRange range = YMFeedViewCountRange(base.string);
        if (range.location == NSNotFound) continue;
        found = YES;
        objc_setAssociatedObject(node, "YMFeedBaseText", base, OBJC_ASSOCIATION_COPY_NONATOMIC);
        NSNumber *lines = objc_getAssociatedObject(node, "YMFeedBaseLines");
        if (!lines) {
            lines = @(node.maximumNumberOfLines);
            objc_setAssociatedObject(node, "YMFeedBaseLines", lines, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!votes) {
            node.maximumNumberOfLines = lines.unsignedIntegerValue;
            YMSetFeedVoteText(node, base);
            continue;
        }
        NSMutableString *counts = [NSMutableString string];
        if (IS_ENABLED(RYDShowLikes)) [counts appendFormat:@" · 👍 %@", YouModFormatVoteCount([votes[@"likes"] integerValue])];
        if (IS_ENABLED(RYDShowDislikes)) [counts appendFormat:@" · 👎 %@", YouModFormatVoteCount([votes[@"dislikes"] integerValue])];
        NSMutableDictionary *attributes = [[base attributesAtIndex:NSMaxRange(range) - 1 effectiveRange:NULL] mutableCopy];
        [attributes removeObjectForKey:NSAttachmentAttributeName];
        NSMutableAttributedString *value = [base mutableCopy];
        [value insertAttributedString:[[NSAttributedString alloc] initWithString:counts attributes:attributes] atIndex:NSMaxRange(range)];
        // Let native text measurement wrap the extra metadata on narrow cards.
        if (node.maximumNumberOfLines != 0) node.maximumNumberOfLines = 0;
        YMSetFeedVoteText(node, value);
    }
    if (found && enabled && !votes) [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoID completion:nil];
}

%hook ASTextNode
- (void)setAttributedText:(NSAttributedString *)text {
    if (!objc_getAssociatedObject(self, "YMSettingFeedVotes") &&
        ![text.string isEqual:objc_getAssociatedObject(self, "YMFeedRenderedText")]) {
        NSNumber *lines = objc_getAssociatedObject(self, "YMFeedBaseLines");
        if (lines) self.maximumNumberOfLines = lines.unsignedIntegerValue;
        objc_setAssociatedObject(self, "YMFeedBaseLines", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "YMFeedBaseText", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}
%end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMReturnDislikeNotification object:nil];
    if (!self.window || !YouModIsOverflowButtonView(self)) return;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_refreshFeedVotes:) name:kYMReturnDislikeNotification object:nil];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    %orig;
    YMUpdateFeedVotes(self);
}
%new
- (void)youmod_refreshFeedVotes:(NSNotification *)note {
    // Resolve the current thumbnail again; a recycled cell may now be another video.
    YMUpdateFeedVotes(self);
}
%end

#pragma mark - Protobuf Model Hooks

%hook YTILikeButtonRenderer

- (BOOL)hasDislikeCountText {
    if (IS_ENABLED(ReturnYouTubeDislike)) return YES;
    return %orig;
}

- (YTIFormattedString *)dislikeCountText {
    if (!IS_ENABLED(ReturnYouTubeDislike)) return %orig;
    NSString *videoId = self.target.videoId;
    if (videoId.length == 0) videoId = YouModGetCurrentVideoID();
    if (videoId.length == 0) return %orig;

    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoId];
    if (votes) {
        NSInteger dislikes = [votes[@"dislikes"] integerValue];
        return [%c(YTIFormattedString) formattedStringWithString:YouModFormatVoteCount(dislikes)];
    }
    [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoId completion:nil];
    return %orig;
}

- (BOOL)hasDislikeCountWithDislikeText {
    if (IS_ENABLED(ReturnYouTubeDislike)) return YES;
    return %orig;
}

- (YTIFormattedString *)dislikeCountWithDislikeText {
    if (!IS_ENABLED(ReturnYouTubeDislike)) return %orig;
    NSString *videoId = self.target.videoId;
    if (videoId.length == 0) videoId = YouModGetCurrentVideoID();
    if (videoId.length == 0) return %orig;

    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoId];
    if (votes) {
        NSInteger dislikes = [votes[@"dislikes"] integerValue] + 1;
        return [%c(YTIFormattedString) formattedStringWithString:YouModFormatVoteCount(dislikes)];
    }
    return %orig;
}

- (BOOL)hasDislikeCountWithUndislikeText {
    if (IS_ENABLED(ReturnYouTubeDislike)) return YES;
    return %orig;
}

- (YTIFormattedString *)dislikeCountWithUndislikeText {
    if (!IS_ENABLED(ReturnYouTubeDislike)) return %orig;
    NSString *videoId = self.target.videoId;
    if (videoId.length == 0) videoId = YouModGetCurrentVideoID();
    if (videoId.length == 0) return %orig;

    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoId];
    if (votes) {
        NSInteger dislikes = [votes[@"dislikes"] integerValue];
        return [%c(YTIFormattedString) formattedStringWithString:YouModFormatVoteCount(dislikes)];
    }
    return %orig;
}

%end

// YouTube Shorts like/dislike counts
static void YouModApplyShortsOverlayVotes(UIView *overlayView) {
    if (!overlayView || !IS_ENABLED(ReturnYouTubeDislike)) return;
    id spvc = [overlayView _viewControllerForAncestor];
    NSString *videoId = nil;
    @try {
        videoId = [spvc valueForKeyPath:@"currentReelNonVideoContentModel.contentVideoId"];
    } @catch (id ex) {}
    if (videoId.length == 0) {
        @try {
            id entry = [spvc valueForKeyPath:@"currentReelVideoModel"];
            videoId = [entry valueForKey:@"videoId"];
        } @catch (id ex) {}
    }
    if (videoId.length == 0) {
        @try {
            id model = [spvc valueForKey:@"_model"];
            videoId = [model valueForKeyPath:@"endpoint.reelWatchEndpoint.videoId"];
            if (videoId.length == 0) videoId = [model valueForKeyPath:@"command.reelWatchEndpoint.videoId"];
        } @catch (id ex) {}
    }
    if (videoId.length == 0) videoId = YouModGetCurrentVideoID();
    if (videoId.length == 0) return;

    // Elements path for Shorts
    UIView *elmView = nil;
    @try { elmView = [overlayView valueForKey:@"_actionBarView"]; } @catch (id ex) {}
    if (!elmView) {
        @try {
            id view = [overlayView valueForKey:@"_actionBarComponentView"];
            elmView = [view valueForKey:@"_elementView"];
        } @catch (id ex) {}
    }
    BOOL isNested = NO;
    if (!elmView) {
        @try {
            id pView = [overlayView valueForKey:@"_playerOverlayView"];
            elmView = [pView valueForKey:@"_elementView"];
            isNested = YES;
        } @catch (id ex) {}
    }

    ELMTextNode *__block shortLikeTextNode = nil;
    ELMTextNode *__block shortDislikeTextNode = nil;

    if (elmView) {
        @try {
            ELMContainerNode *containerNode = nil;
            if (isNested) {
                ELMContainerNode *node = [elmView valueForKey:@"_rootNode"];
                node = [node.yogaChildren firstObject];
                if (node.yogaChildren.count >= 2) containerNode = node.yogaChildren[1];
            } else {
                containerNode = [elmView valueForKey:@"_rootNode"];
            }
            if (containerNode && containerNode.yogaChildren.count >= 2) {
                ELMContainerNode *likeNode = [containerNode.yogaChildren firstObject];
                ELMContainerNode *dislikeNode = containerNode.yogaChildren[1];
                while (likeNode.yogaChildren.count == 1) likeNode = [likeNode.yogaChildren firstObject];
                while (dislikeNode.yogaChildren.count == 1) dislikeNode = [dislikeNode.yogaChildren firstObject];

                NSArray *likeChildren = likeNode.yogaChildren;
                if (likeChildren.count == 1) likeChildren = ((ASDisplayNode *)[likeNode.yogaChildren firstObject]).yogaChildren;
                if (likeChildren.count >= 2 && [likeChildren[1] isKindOfClass:%c(ELMTextNode)]) {
                    shortLikeTextNode = likeChildren[1];
                }

                NSArray *dislikeChildren = dislikeNode.yogaChildren;
                if (dislikeChildren.count == 1) dislikeChildren = ((ASDisplayNode *)[dislikeNode.yogaChildren firstObject]).yogaChildren;
                if (dislikeChildren.count >= 2 && [dislikeChildren[1] isKindOfClass:%c(ELMTextNode)]) {
                    shortDislikeTextNode = dislikeChildren[1];
                }
            }
        } @catch (id ex) {}
    }

    [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoId completion:^(NSDictionary *votes) {
        if (!votes) return;
        NSInteger dislikes = [votes[@"dislikes"] integerValue];
        NSString *dislikesText = YouModFormatVoteCount(dislikes);
        NSInteger likes = [votes[@"likes"] integerValue];
        NSString *likesText = YouModFormatVoteCount(likes);

        dispatch_async(dispatch_get_main_queue(), ^{
            // Update Elements nodes
            if (shortLikeTextNode && IS_ENABLED(RYDShowLikes)) {
                NSMutableAttributedString *mLike = [[NSMutableAttributedString alloc] initWithAttributedString:shortLikeTextNode.attributedText];
                [mLike.mutableString setString:likesText];
                shortLikeTextNode.attributedText = mLike;
                shortLikeTextNode.accessibilityLabel = likesText;
                [shortLikeTextNode setNeedsDisplay];
            }
            if (shortDislikeTextNode && IS_ENABLED(RYDShowDislikes)) {
                NSMutableAttributedString *mDis = [[NSMutableAttributedString alloc] initWithAttributedString:shortDislikeTextNode.attributedText];
                [mDis.mutableString setString:dislikesText];
                shortDislikeTextNode.attributedText = mDis;
                shortDislikeTextNode.accessibilityLabel = dislikesText;
                [shortDislikeTextNode setNeedsDisplay];
            }

            // Update UIKit fallback buttons
            for (UIView *v in overlayView.subviews) {
                if ([v.accessibilityIdentifier isEqualToString:@"id.reel_dislike_button"] || [v.accessibilityIdentifier isEqualToString:@"id.video.dislike.button"]) {
                    if ([v respondsToSelector:@selector(setTitle:forState:)]) {
                        [(UIButton *)v setTitle:dislikesText forState:UIControlStateNormal];
                        [(UIButton *)v setTitle:dislikesText forState:UIControlStateSelected];
                    }
                }
                if (IS_ENABLED(RYDShowLikes) && ([v.accessibilityIdentifier isEqualToString:@"id.reel_like_button"] || [v.accessibilityIdentifier isEqualToString:@"id.video.like.button"])) {
                    if ([v respondsToSelector:@selector(setTitle:forState:)]) {
                        [(UIButton *)v setTitle:likesText forState:UIControlStateNormal];
                        [(UIButton *)v setTitle:likesText forState:UIControlStateSelected];
                    }
                }
            }
        });
    }];
}

%hook YTReelWatchPlaybackOverlayView
- (void)layoutActionBar {
    %orig;
    YouModApplyShortsOverlayVotes(self);
}
%end

%hook YTReelWatchPlaybackOverlayViewSub
- (void)layoutActionBar {
    %orig;
    YouModApplyShortsOverlayVotes((UIView *)self);
}
%end

%hook YTReelWatchLikesController

- (void)updateLikeButtonWithRenderer:(id)renderer {
    %orig;
    if (!IS_ENABLED(ReturnYouTubeDislike)) return;

    NSString *vID = nil;
    @try {
        vID = [renderer valueForKeyPath:@"target.videoId"];
    } @catch (id ex) {}

    if (vID.length == 0) vID = YouModGetCurrentVideoID();
    if (vID.length == 0) return;

    YTQTMButton *dislikeBtn = nil;
    YTQTMButton *likeBtn = nil;
    @try {
        dislikeBtn = [(id)self valueForKey:@"dislikeButton"];
        likeBtn = [(id)self valueForKey:@"likeButton"];
    } @catch (id ex) {}

    [[YouModRYDManager sharedInstance] fetchVotesForVideoID:vID completion:^(NSDictionary *votes) {
        if (!votes) return;
        NSInteger dislikes = [votes[@"dislikes"] integerValue];
        NSString *formattedDislikes = YouModFormatVoteCount(dislikes);
        NSInteger likes = [votes[@"likes"] integerValue];
        NSString *formattedLikes = YouModFormatVoteCount(likes);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (dislikeBtn && [dislikeBtn respondsToSelector:@selector(setTitle:forState:)]) {
                [dislikeBtn setTitle:formattedDislikes forState:UIControlStateNormal];
                [dislikeBtn setTitle:formattedDislikes forState:UIControlStateSelected];
            }
            if (likeBtn && IS_ENABLED(RYDShowLikes) && [likeBtn respondsToSelector:@selector(setTitle:forState:)]) {
                [likeBtn setTitle:formattedLikes forState:UIControlStateNormal];
                [likeBtn setTitle:formattedLikes forState:UIControlStateSelected];
            }
        });
    }];
}

%end

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        ReturnYouTubeDislike: @YES,
        RYDShowLikes: @YES,
        RYDShowDislikes: @YES,
        @"RYD-ENABLED": @YES,
        @"RYD-USE-LIKE-DATA": @YES,
        @"RYD-EXACT-NUMBER": @NO
    }];
}
