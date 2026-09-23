#import "Headers.h"

// DeArrow Integration for YouTube iOS (YouMod)
// API: https://sponsor.ajay.app/api/branding?videoID={videoID}
// Thumbnails: https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID={videoID}&time={timestamp}

static NSString * const kYMDeArrowUpdatedNotification = @"YouModDeArrowUpdatedNotification";
static NSString *currentInlinePreviewVideoID = nil;

@interface YouModDeArrowManager : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *brandingCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
@property (nonatomic, strong) NSMutableSet<NSString *> *toggledOriginalVideoIDs;
+ (instancetype)sharedInstance;
- (void)fetchBrandingForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *branding))completion;
- (void)prefetchBrandingForVideoID:(NSString *)videoID;
- (NSString *)titleForVideoID:(NSString *)videoID;
- (NSString *)originalTitleForVideoID:(NSString *)videoID;
- (NSString *)thumbnailURLForVideoID:(NSString *)videoID;
- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID;
- (BOOL)toggleDeArrowForVideoID:(NSString *)videoID;
- (BOOL)hasDeArrowBrandingForVideoID:(NSString *)videoID;
@end

@implementation YouModDeArrowManager

+ (instancetype)sharedInstance {
    static YouModDeArrowManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YouModDeArrowManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _brandingCache = [[NSCache alloc] init];
        _brandingCache.countLimit = 500;
        _inFlightRequests = [NSMutableSet set];
        _toggledOriginalVideoIDs = [NSMutableSet set];
    }
    return self;
}

- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID {
    if (!videoID) return NO;
    @synchronized (_toggledOriginalVideoIDs) {
        return [_toggledOriginalVideoIDs containsObject:videoID];
    }
}

- (BOOL)hasDeArrowBrandingForVideoID:(NSString *)videoID {
    if (!videoID) return NO;
    NSDictionary *entry = [_brandingCache objectForKey:videoID];
    if (!entry) return NO;
    return (entry[@"title"] != nil || entry[@"thumbnailURL"] != nil);
}

- (BOOL)toggleDeArrowForVideoID:(NSString *)videoID {
    if (!videoID) return NO;
    BOOL nowOriginal = NO;
    @synchronized (_toggledOriginalVideoIDs) {
        if ([_toggledOriginalVideoIDs containsObject:videoID]) {
            [_toggledOriginalVideoIDs removeObject:videoID];
            nowOriginal = NO;
        } else {
            [_toggledOriginalVideoIDs addObject:videoID];
            nowOriginal = YES;
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification
                                                            object:nil
                                                          userInfo:@{@"videoID": videoID, @"isOriginal": @(nowOriginal)}];
    });
    return nowOriginal;
}

- (NSString *)titleForVideoID:(NSString *)videoID {
    if (!videoID || videoID.length == 0) return nil;
    if ([self isOriginalToggledForVideoID:videoID]) {
        NSDictionary *entry = [_brandingCache objectForKey:videoID];
        return entry[@"originalTitle"];
    }
    NSDictionary *entry = [_brandingCache objectForKey:videoID];
    if (entry) {
        NSString *title = entry[@"title"];
        if (title.length > 0) return title;
        if (IS_ENABLED(DeArrowFallbackToOriginal)) {
            return entry[@"originalTitle"];
        }
    }
    return nil;
}

- (NSString *)originalTitleForVideoID:(NSString *)videoID {
    if (!videoID || videoID.length == 0) return nil;
    NSDictionary *entry = [_brandingCache objectForKey:videoID];
    return entry[@"originalTitle"];
}

- (NSString *)thumbnailURLForVideoID:(NSString *)videoID {
    if (!videoID || videoID.length == 0) return nil;
    if ([self isOriginalToggledForVideoID:videoID]) {
        return nil;
    }
    NSDictionary *entry = [_brandingCache objectForKey:videoID];
    if (entry) {
        NSString *thumb = entry[@"thumbnailURL"];
        if (thumb.length > 0) return thumb;
    }
    return nil;
}

- (void)prefetchBrandingForVideoID:(NSString *)videoID {
    [self fetchBrandingForVideoID:videoID completion:nil];
}

- (void)fetchBrandingForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *branding))completion {
    if (!videoID || videoID.length == 0) {
        if (completion) completion(nil);
        return;
    }

    NSDictionary *cached = [_brandingCache objectForKey:videoID];
    if (cached) {
        if (completion) completion(cached);
        return;
    }

    @synchronized (_inFlightRequests) {
        if ([_inFlightRequests containsObject:videoID]) {
            if (completion) completion(nil);
            return;
        }
        [_inFlightRequests addObject:videoID];
    }

    NSString *urlString = [NSString stringWithFormat:@"https://sponsor.ajay.app/api/branding?videoID=%@", videoID];
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

        NSMutableDictionary *branding = [NSMutableDictionary dictionary];
        branding[@"videoID"] = videoID;

        // Parse Titles
        NSArray *titles = json[@"titles"];
        if ([titles isKindOfClass:[NSArray class]] && titles.count > 0) {
            NSDictionary *bestTitleObj = nil;
            NSInteger maxVotes = -999999;
            for (NSDictionary *tObj in titles) {
                if (![tObj isKindOfClass:[NSDictionary class]]) continue;
                BOOL isOriginal = [tObj[@"original"] boolValue];
                BOOL isLocked = [tObj[@"locked"] boolValue];
                NSInteger votes = [tObj[@"votes"] integerValue];
                if (isOriginal && !branding[@"originalTitle"]) {
                    branding[@"originalTitle"] = tObj[@"title"];
                }
                if (!isOriginal) {
                    if (isLocked) {
                        bestTitleObj = tObj;
                        break;
                    }
                    if (votes > maxVotes) {
                        maxVotes = votes;
                        bestTitleObj = tObj;
                    }
                }
            }
            if (bestTitleObj && bestTitleObj[@"title"]) {
                branding[@"title"] = bestTitleObj[@"title"];
            }
        }

        // Parse Thumbnails
        NSArray *thumbnails = json[@"thumbnails"];
        NSNumber *bestTimestamp = nil;
        if ([thumbnails isKindOfClass:[NSArray class]] && thumbnails.count > 0) {
            NSInteger maxVotes = -999999;
            for (NSDictionary *thObj in thumbnails) {
                if (![thObj isKindOfClass:[NSDictionary class]]) continue;
                BOOL isOriginal = [thObj[@"original"] boolValue];
                BOOL isLocked = [thObj[@"locked"] boolValue];
                id tsVal = thObj[@"timestamp"];
                if (isOriginal) continue;
                if (tsVal == nil || [tsVal isKindOfClass:[NSNull class]]) continue;
                NSInteger votes = [thObj[@"votes"] integerValue];
                if (isLocked) {
                    bestTimestamp = @([tsVal doubleValue]);
                    break;
                }
                if (votes > maxVotes) {
                    maxVotes = votes;
                    bestTimestamp = @([tsVal doubleValue]);
                }
            }
        }

        if (!bestTimestamp && json[@"randomTime"] && ![json[@"randomTime"] isKindOfClass:[NSNull class]]) {
            bestTimestamp = @([json[@"randomTime"] doubleValue]);
        }

        if (bestTimestamp) {
            branding[@"timestamp"] = bestTimestamp;
            branding[@"thumbnailURL"] = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@&time=%@", videoID, bestTimestamp];
        }

        [self.brandingCache setObject:branding forKey:videoID];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification
                                                                object:nil
                                                              userInfo:@{@"videoID": videoID, @"branding": branding}];
            if (completion) completion(branding);
        });
    }];
    [task resume];
}

@end

// Helper to extract 11-char YouTube video ID from standard thumbnail URLs
static NSString *YouModExtractDeArrowVideoID(NSString *urlStr) {
    if (!urlStr || urlStr.length < 15) return nil;
    
    NSArray *prefixes = @[@"/vi/", @"/vi_webp/", @"/an_webp/", @"/v/", @"video_id=", @"v="];
    for (NSString *prefix in prefixes) {
        NSRange range = [urlStr rangeOfString:prefix];
        if (range.location != NSNotFound) {
            NSUInteger start = range.location + prefix.length;
            if (start + 11 <= urlStr.length) {
                NSString *candidate = [urlStr substringWithRange:NSMakeRange(start, 11)];
                if (![candidate containsString:@"/"] && ![candidate containsString:@"?"] && ![candidate containsString:@"&"]) {
                    return candidate;
                }
            }
        }
    }
    return nil;
}

#pragma mark - Live Thumbnail Hooks

// AsyncDisplayKit network image hook
%hook ASNetworkImageNode

- (void)setURL:(NSURL *)url resetToDefault:(BOOL)reset {
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails) || !url) {
        %orig(url, reset);
        return;
    }

    NSString *urlStr = url.absoluteString;
    NSString *videoID = YouModExtractDeArrowVideoID(urlStr);
    if (!videoID || videoID.length != 11) {
        %orig(url, reset);
        return;
    }

    objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "kYMDeArrowOrigURLKey", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if (v) objc_setAssociatedObject(v, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if ([[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
        %orig(url, reset);
        return;
    }

    NSString *deArrowURL = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
    if (deArrowURL.length > 0) {
        %orig([NSURL URLWithString:deArrowURL], reset);
        return;
    }

    %orig(url, reset);
    __weak ASNetworkImageNode *weakSelf = self;
    [[YouModDeArrowManager sharedInstance] fetchBrandingForVideoID:videoID completion:^(NSDictionary *branding) {
        ASNetworkImageNode *strongSelf = weakSelf;
        if (!strongSelf || !branding) return;
        NSString *thumb = branding[@"thumbnailURL"];
        if (thumb.length > 0 && ![[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
            NSString *curID = objc_getAssociatedObject(strongSelf, "kYMDeArrowVideoIDKey");
            if ([curID isEqualToString:videoID]) {
                [strongSelf setURL:[NSURL URLWithString:thumb] resetToDefault:NO];
                [strongSelf setNeedsDisplay];
            }
        }
    }];
}

- (void)setURL:(NSURL *)url {
    [self setURL:url resetToDefault:YES];
}

- (void)didLoad {
    %orig;
    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (videoID && [self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if (v) objc_setAssociatedObject(v, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

// UIKit image view hook
%hook YTImageView

- (void)setImageWithURL:(NSURL *)url {
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails) || !url) {
        %orig(url);
        return;
    }

    NSString *urlStr = url.absoluteString;
    NSString *videoID = YouModExtractDeArrowVideoID(urlStr);
    if (!videoID || videoID.length != 11) {
        %orig(url);
        return;
    }

    objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "kYMDeArrowOrigURLKey", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
        %orig(url);
        return;
    }

    NSString *deArrowURL = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
    if (deArrowURL.length > 0) {
        %orig([NSURL URLWithString:deArrowURL]);
        return;
    }

    %orig(url);
    __weak YTImageView *weakSelf = self;
    [[YouModDeArrowManager sharedInstance] fetchBrandingForVideoID:videoID completion:^(NSDictionary *branding) {
        YTImageView *strongSelf = weakSelf;
        if (!strongSelf || !branding) return;
        NSString *thumb = branding[@"thumbnailURL"];
        if (thumb.length > 0 && ![[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
            NSString *curID = objc_getAssociatedObject(strongSelf, "kYMDeArrowVideoIDKey");
            if ([curID isEqualToString:videoID]) {
                [strongSelf setImageWithURL:[NSURL URLWithString:thumb]];
                [strongSelf setNeedsDisplay];
            }
        }
    }];
}

%end

// Protobuf model thumbnail fallback
%hook YTIThumbnailDetails_Thumbnail
- (NSString *)URL {
    NSString *origURL = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails)) {
        return origURL;
    }
    NSString *videoID = YouModExtractDeArrowVideoID(origURL);
    if (!videoID || videoID.length != 11) return origURL;

    NSString *deArrowURL = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
    if (deArrowURL) {
        return deArrowURL;
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
    return origURL;
}
%end

#pragma mark - Title Hooks across All Feed & Video Renderers

// Home / subscriptions main feed video renderer
%hook YTIVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origTitle;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origTitle;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        Class fmtClass = %c(YTIFormattedString);
        if ([fmtClass respondsToSelector:@selector(formattedStringWithString:)]) {
            return [fmtClass formattedStringWithString:deArrowTitle];
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

// Video with context renderer (rich feed layouts)
%hook YTIVideoWithContextRenderer
- (YTIFormattedString *)headline {
    YTIFormattedString *origHeadline = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origHeadline;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origHeadline;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        Class fmtClass = %c(YTIFormattedString);
        if ([fmtClass respondsToSelector:@selector(formattedStringWithString:)]) {
            return [fmtClass formattedStringWithString:deArrowTitle];
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origHeadline;
}
%end

// Grid video renderer (search & channel video grids)
%hook YTIGridVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origTitle;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origTitle;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        Class fmtClass = %c(YTIFormattedString);
        if ([fmtClass respondsToSelector:@selector(formattedStringWithString:)]) {
            return [fmtClass formattedStringWithString:deArrowTitle];
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

// Compact video renderer (search / related under player)
%hook YTICompactVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origTitle;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origTitle;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        Class fmtClass = %c(YTIFormattedString);
        if ([fmtClass respondsToSelector:@selector(formattedStringWithString:)]) {
            return [fmtClass formattedStringWithString:deArrowTitle];
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

// Playlist video renderer
%hook YTIPlaylistVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origTitle;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origTitle;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        Class fmtClass = %c(YTIFormattedString);
        if ([fmtClass respondsToSelector:@selector(formattedStringWithString:)]) {
            return [fmtClass formattedStringWithString:deArrowTitle];
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

// Playlist panel video renderer
%hook YTIPlaylistPanelVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origTitle;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origTitle;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        Class fmtClass = %c(YTIFormattedString);
        if ([fmtClass respondsToSelector:@selector(formattedStringWithString:)]) {
            return [fmtClass formattedStringWithString:deArrowTitle];
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

// Video details title in player
%hook YTIVideoDetails
- (NSString *)title {
    NSString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) return origTitle;
    NSString *vID = self.videoId;
    if (vID.length == 0) return origTitle;

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        return deArrowTitle;
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

// Player response trigger to prefetch branding as soon as a video starts
%hook YTPlayerViewController
- (void)setPlayerResponse:(YTIPlayerResponse *)response {
    %orig;
    if (IS_ENABLED(DeArrowEnabled) && response.videoDetails.videoId.length > 0) {
        [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:response.videoDetails.videoId];
    }
}
%end

#pragma mark - DeArrow Indicator & Feed Preview Quick Swap

@interface YouModDeArrowSwapHandler : NSObject
+ (instancetype)sharedHandler;
- (void)handleSwapGesture:(UILongPressGestureRecognizer *)gesture;
- (void)handleSwapButtonTap:(UIButton *)button;
- (void)handlePreviewOverlayTap:(UIButton *)button;
@end

@implementation YouModDeArrowSwapHandler

+ (instancetype)sharedHandler {
    static YouModDeArrowSwapHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[YouModDeArrowSwapHandler alloc] init];
    });
    return instance;
}

- (void)triggerSwapForVideoID:(NSString *)videoID fromView:(UIView *)targetView {
    if (!videoID || videoID.length == 0) return;
    BOOL isNowOriginal = [[YouModDeArrowManager sharedInstance] toggleDeArrowForVideoID:videoID];

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback prepare];
    [feedback impactOccurred];

    NSString *status = isNowOriginal ? @"DeArrow: Off (Original)" : @"DeArrow: On (Replaced)";
    Class hudClass = %c(GOOHUDManagerInternal);
    SEL sel = NSSelectorFromString(@"showMessageWithText:");
    if ([hudClass respondsToSelector:sel]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [hudClass performSelector:sel withObject:status];
        #pragma clang diagnostic pop
    }

    if (targetView) {
        [targetView setNeedsLayout];
        [targetView setNeedsDisplay];
        UIView *parent = targetView.superview;
        while (parent && ![parent isKindOfClass:%c(_ASCollectionViewCell)] && ![parent isKindOfClass:[UICollectionViewCell class]]) {
            parent = parent.superview;
        }
        if (parent) {
            [parent setNeedsLayout];
            [parent setNeedsDisplay];
        }
    }
}

- (void)handleSwapGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIView *view = gesture.view;
    NSString *videoID = objc_getAssociatedObject(view, "kYMDeArrowVideoIDKey");
    if (!videoID) return;
    [self triggerSwapForVideoID:videoID fromView:view];
}

- (void)handleSwapButtonTap:(UIButton *)button {
    NSString *videoID = objc_getAssociatedObject(button, "kYMDeArrowVideoIDKey");
    if (!videoID) return;
    [self triggerSwapForVideoID:videoID fromView:button.superview];
}

- (void)handlePreviewOverlayTap:(UIButton *)button {
    NSString *videoID = objc_getAssociatedObject(button, "kYMDeArrowVideoIDKey");
    if (!videoID && currentInlinePreviewVideoID.length > 0) {
        videoID = currentInlinePreviewVideoID;
    }
    if (!videoID) return;
    [self triggerSwapForVideoID:videoID fromView:button.superview];
}

@end

// Update indicator badge styling
static void YouModUpdateIndicatorBadge(UIButton *badgeBtn, NSString *videoID) {
    if (!badgeBtn || !videoID) return;
    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID];
    BOOL hasBranding = [[YouModDeArrowManager sharedInstance] hasDeArrowBrandingForVideoID:videoID];

    if (!hasBranding && !isOriginal) {
        badgeBtn.hidden = YES;
        return;
    }

    badgeBtn.hidden = NO;
    if (isOriginal) {
        [badgeBtn setTitle:@"Original" forState:UIControlStateNormal];
        badgeBtn.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.75];
        [badgeBtn setTitleColor:[UIColor colorWithWhite:0.8 alpha:1.0] forState:UIControlStateNormal];
    } else {
        [badgeBtn setTitle:@"⚡ DeArrow" forState:UIControlStateNormal];
        badgeBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.45 blue:0.9 alpha:0.8];
        [badgeBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    }
}

// Robust helper to extract video ID from an ASDisplayView or its hierarchy
static NSString *YouModFindVideoIDFromView(UIView *view) {
    if (!view) return nil;
    NSString *vID = objc_getAssociatedObject(view, "kYMDeArrowVideoIDKey");
    if (vID.length == 11) return vID;

    // Check node associated with view
    id node = nil;
    if ([view respondsToSelector:@selector(node)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        node = [view performSelector:@selector(node)];
        #pragma clang diagnostic pop
    }
    if (!node) {
        @try { node = [view valueForKey:@"asyncdisplaykit_node"]; } @catch (id ex) {}
    }
    if (node) {
        NSString *nodeVID = objc_getAssociatedObject(node, "kYMDeArrowVideoIDKey");
        if (nodeVID.length == 11) return nodeVID;
        if ([node respondsToSelector:@selector(URL)]) {
            NSURL *u = [node performSelector:@selector(URL)];
            NSString *extracted = YouModExtractDeArrowVideoID(u.absoluteString);
            if (extracted.length == 11) return extracted;
        }
    }

    // Check subviews
    for (UIView *sub in view.subviews) {
        NSString *subVID = objc_getAssociatedObject(sub, "kYMDeArrowVideoIDKey");
        if (subVID.length == 11) return subVID;
        id subNode = nil;
        if ([sub respondsToSelector:@selector(node)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            subNode = [sub performSelector:@selector(node)];
            #pragma clang diagnostic pop
        }
        if (!subNode) {
            @try { subNode = [sub valueForKey:@"asyncdisplaykit_node"]; } @catch (id ex) {}
        }
        if (subNode) {
            NSString *snVID = objc_getAssociatedObject(subNode, "kYMDeArrowVideoIDKey");
            if (snVID.length == 11) return snVID;
            if ([subNode respondsToSelector:@selector(URL)]) {
                NSURL *u = [subNode performSelector:@selector(URL)];
                NSString *extracted = YouModExtractDeArrowVideoID(u.absoluteString);
                if (extracted.length == 11) return extracted;
            }
        }
    }

    // Fallback to description inspection
    return YouModExtractDeArrowVideoID([view description]);
}

#pragma mark - Visual Indicator & Feed Preview Cell Overlay

%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
        return;
    }
    if (!IS_ENABLED(DeArrowEnabled)) return;

    NSString *iden = self.accessibilityIdentifier;
    if (iden.length == 0) return;

    if ([iden containsString:@"thumbnail"] || [iden containsString:@"compact_video"] || [iden containsString:@"video_with_context"]) {
        NSString *videoID = YouModFindVideoIDFromView(self);
        if (videoID && videoID.length == 11) {
            objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            if (IS_ENABLED(DeArrowQuickSwap)) {
                BOOL hasLongPress = NO;
                for (UIGestureRecognizer *gr in self.gestureRecognizers) {
                    if ([gr isKindOfClass:[UILongPressGestureRecognizer class]] && [gr.name isEqualToString:@"YMDeArrowSwap"]) {
                        hasLongPress = YES;
                        break;
                    }
                }
                if (!hasLongPress) {
                    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapGesture:)];
                    lp.name = @"YMDeArrowSwap";
                    lp.minimumPressDuration = 0.35;
                    [self addGestureRecognizer:lp];
                }
            }

            // Indicator Badge
            if ([iden containsString:@"thumbnail"]) {
                UIButton *badgeBtn = (UIButton *)[self viewWithTag:0xDEA220];
                if (!badgeBtn) {
                    badgeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
                    badgeBtn.tag = 0xDEA220;
                    badgeBtn.frame = CGRectMake(6, 6, 74, 22);
                    badgeBtn.layer.cornerRadius = 4;
                    badgeBtn.layer.masksToBounds = YES;
                    badgeBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
                    [badgeBtn addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapButtonTap:) forControlEvents:UIControlEventTouchUpInside];
                    [self addSubview:badgeBtn];
                }
                objc_setAssociatedObject(badgeBtn, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                YouModUpdateIndicatorBadge(badgeBtn, videoID);

                // Listen for DeArrow branding updates to show badge once fetched
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowNotification:) name:kYMDeArrowUpdatedNotification object:nil];
            }
        }
    }
}

%new
- (void)youmod_onDeArrowNotification:(NSNotification *)notif {
    NSString *notifVideoID = notif.userInfo[@"videoID"];
    NSString *myVideoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!myVideoID || ![myVideoID isEqualToString:notifVideoID]) return;

    UIButton *badgeBtn = (UIButton *)[self viewWithTag:0xDEA220];
    if (badgeBtn) {
        YouModUpdateIndicatorBadge(badgeBtn, myVideoID);
    }
}

%end

#pragma mark - Preview Button Overlay on Video Playback Previews (Inline Muted Playback)

// Track active preview video ID
%hook YTInlineMutedPlaybackScrubberViewController

- (void)setActiveSingleVideoObservable:(YTSingleVideoController *)singleVideoController {
    %orig;
    if (singleVideoController) {
        @try {
            NSString *vID = [singleVideoController valueForKey:@"_videoId"];
            if (!vID && [singleVideoController respondsToSelector:@selector(contentVideoID)]) {
                vID = [singleVideoController performSelector:@selector(contentVideoID)];
            }
            if (!vID && [singleVideoController respondsToSelector:@selector(videoId)]) {
                vID = [singleVideoController performSelector:@selector(videoId)];
            }
            if (vID.length > 0) {
                currentInlinePreviewVideoID = [vID copy];
                if (self.view.superview) {
                    objc_setAssociatedObject(self.view.superview, "kYMDeArrowVideoIDKey", currentInlinePreviewVideoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        } @catch (id ex) {}
    }
}

%end

// Add DeArrow toggle button to the inline preview overlay
%hook YTInlineMutedPlaybackPlayerOverlayView

- (void)layoutSubviews {
    %orig;
    if (!IS_ENABLED(DeArrowEnabled)) {
        UIView *btn = [self viewWithTag:0xDEA221];
        if (btn) btn.hidden = YES;
        return;
    }

    UIButton *deArrowBtn = (UIButton *)[self viewWithTag:0xDEA221];
    if (!deArrowBtn) {
        deArrowBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        deArrowBtn.tag = 0xDEA221;
        deArrowBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
        deArrowBtn.layer.cornerRadius = 16;
        deArrowBtn.layer.masksToBounds = YES;
        [deArrowBtn addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handlePreviewOverlayTap:) forControlEvents:UIControlEventTouchUpInside];

        UIImageSymbolConfiguration *symConfig = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIFontWeightBold];
        UIImage *swapImg = [UIImage systemImageNamed:@"arrow.triangle.swap" withConfiguration:symConfig];
        if (!swapImg) swapImg = [UIImage systemImageNamed:@"arrow.2.squarepath" withConfiguration:symConfig];
        [deArrowBtn setImage:swapImg forState:UIControlStateNormal];

        [self addSubview:deArrowBtn];
    }

    deArrowBtn.hidden = NO;
    NSString *activeVID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!activeVID && currentInlinePreviewVideoID.length > 0) {
        activeVID = currentInlinePreviewVideoID;
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", activeVID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(deArrowBtn, "kYMDeArrowVideoIDKey", activeVID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:activeVID];
    if (isOriginal) {
        deArrowBtn.tintColor = [UIColor colorWithWhite:0.6 alpha:1.0];
        deArrowBtn.alpha = 0.6;
    } else {
        deArrowBtn.tintColor = [UIColor colorWithRed:0.24 green:0.65 blue:1.0 alpha:1.0]; // YouTube blue tint
        deArrowBtn.alpha = 1.0;
    }

    // Position next to the mute button or top right
    UIView *soundIconView = [self valueForKey:@"_audioSoundIconView"];
    if (soundIconView && !soundIconView.hidden) {
        CGRect soundFrame = soundIconView.frame;
        CGFloat btnSize = 32.0;
        deArrowBtn.frame = CGRectMake(soundFrame.origin.x - btnSize - 8.0, soundFrame.origin.y + (soundFrame.size.height - btnSize) / 2.0, btnSize, btnSize);
    } else {
        CGFloat btnSize = 32.0;
        CGFloat topMargin = 12.0;
        CGFloat rightMargin = 12.0;
        deArrowBtn.frame = CGRectMake(self.bounds.size.width - rightMargin - btnSize, topMargin, btnSize, btnSize);
    }
}

%end

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        DeArrowEnabled: @YES,
        DeArrowReplaceTitles: @YES,
        DeArrowReplaceThumbnails: @YES,
        DeArrowFallbackToOriginal: @YES,
        DeArrowQuickSwap: @YES
    }];
}
