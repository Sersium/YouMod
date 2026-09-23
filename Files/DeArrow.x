#import "Headers.h"

// DeArrow Integration for YouTube iOS (YouMod)
// API: https://sponsor.ajay.app/api/branding?videoID={videoID}
// Thumbnails: https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID={videoID}&time={timestamp}

@interface YouModDeArrowManager : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *brandingCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
@property (nonatomic, strong) NSMutableSet<NSString *> *toggledOriginalVideoIDs;
+ (instancetype)sharedInstance;
- (void)fetchBrandingForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *branding))completion;
- (void)prefetchBrandingForVideoID:(NSString *)videoID;
- (NSString *)titleForVideoID:(NSString *)videoID;
- (NSString *)thumbnailURLForVideoID:(NSString *)videoID;
- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID;
- (BOOL)toggleDeArrowForVideoID:(NSString *)videoID;
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
    request.timeoutInterval = 6.0;
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

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(branding);
            });
        }
    }];
    [task resume];
}

@end

// Helper to extract 11-char YouTube video ID from standard thumbnail URLs
static NSString *YouModExtractDeArrowVideoID(NSString *urlStr) {
    if (!urlStr || urlStr.length < 15) return nil;
    
    // Look for /vi/, /vi_webp/, or /an_webp/
    NSArray *prefixes = @[@"/vi/", @"/vi_webp/", @"/an_webp/"];
    for (NSString *prefix in prefixes) {
        NSRange range = [urlStr rangeOfString:prefix];
        if (range.location != NSNotFound) {
            NSUInteger start = range.location + prefix.length;
            if (start + 11 <= urlStr.length) {
                NSString *candidate = [urlStr substringWithRange:NSMakeRange(start, 11)];
                // Check if candidate contains path separator or query
                if (![candidate containsString:@"/"] && ![candidate containsString:@"?"]) {
                    return candidate;
                }
            }
        }
    }
    return nil;
}

#pragma mark - Hooks

// Thumbnail replacement
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

// Video details title replacement in player
%hook YTIVideoDetails
- (NSString *)title {
    NSString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) {
        return origTitle;
    }
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

// Feed compact video renderer title replacement
%hook YTICompactVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) {
        return origTitle;
    }
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

// Playlist video renderer title replacement
%hook YTIPlaylistVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) {
        return origTitle;
    }
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

// Playlist panel video renderer title replacement
%hook YTIPlaylistPanelVideoRenderer
- (YTIFormattedString *)title {
    YTIFormattedString *origTitle = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles)) {
        return origTitle;
    }
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

// Player response trigger to prefetch branding as soon as a video is loaded
%hook YTPlayerViewController
- (void)setPlayerResponse:(YTIPlayerResponse *)response {
    %orig;
    if (IS_ENABLED(DeArrowEnabled) && response.videoDetails.videoId.length > 0) {
        [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:response.videoDetails.videoId];
    }
}
%end

@interface YouModDeArrowSwapHandler : NSObject
+ (instancetype)sharedHandler;
- (void)handleSwapGesture:(UILongPressGestureRecognizer *)gesture;
- (void)handleSwapButtonTap:(UIButton *)button;
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

    NSString *status = isNowOriginal ? @"DeArrow: Original" : @"DeArrow: Replaced";
    Class hudClass = %c(GOOHUDManagerInternal);
    if ([hudClass respondsToSelector:@selector(showMessageWithText:)]) {
        [(id)hudClass showMessageWithText:status];
    }

    if (targetView) {
        [targetView setNeedsLayout];
        [targetView setNeedsDisplay];
        UIView *parent = targetView.superview;
        while (parent && ![parent isKindOfClass:%c(_ASCollectionViewCell)]) {
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

@end

%hook _ASDisplayView
- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowQuickSwap)) return;

    NSString *iden = self.accessibilityIdentifier;
    if (iden.length == 0) return;

    if ([iden containsString:@"id.video.thumbnail"] || [iden containsString:@"compact_video"] || [iden containsString:@"video_with_context"]) {
        NSString *videoID = YouModExtractDeArrowVideoID([self description]);
        if (!videoID) {
            for (UIView *sub in self.subviews) {
                videoID = YouModExtractDeArrowVideoID([sub description]);
                if (videoID) break;
            }
        }
        if (videoID && videoID.length == 11) {
            objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

            if ([iden containsString:@"id.video.thumbnail"] && ![self viewWithTag:0xDEA220]) {
                UIButton *badgeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
                badgeBtn.tag = 0xDEA220;
                badgeBtn.frame = CGRectMake(6, 6, 26, 26);
                badgeBtn.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
                badgeBtn.layer.cornerRadius = 13;
                badgeBtn.layer.masksToBounds = YES;
                objc_setAssociatedObject(badgeBtn, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [badgeBtn addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapButtonTap:) forControlEvents:UIControlEventTouchUpInside];

                UIImageSymbolConfiguration *symConfig = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIFontWeightBold];
                UIImage *swapImg = [UIImage systemImageNamed:@"arrow.triangle.swap" withConfiguration:symConfig];
                if (!swapImg) swapImg = [UIImage systemImageNamed:@"arrow.2.squarepath" withConfiguration:symConfig];
                [badgeBtn setImage:swapImg forState:UIControlStateNormal];
                badgeBtn.tintColor = [UIColor whiteColor];
                [self addSubview:badgeBtn];
            }
        }
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
