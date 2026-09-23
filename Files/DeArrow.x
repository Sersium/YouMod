#import "Headers.h"

// DeArrow Integration for YouTube iOS (YouMod)
// API: https://sponsor.ajay.app/api/branding?videoID={videoID}
// Thumbnails: https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID={videoID}&time={timestamp}

@interface YouModDeArrowManager : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *brandingCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
+ (instancetype)sharedInstance;
- (void)fetchBrandingForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *branding))completion;
- (void)prefetchBrandingForVideoID:(NSString *)videoID;
- (NSString *)titleForVideoID:(NSString *)videoID;
- (NSString *)thumbnailURLForVideoID:(NSString *)videoID;
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
    }
    return self;
}

- (NSString *)titleForVideoID:(NSString *)videoID {
    if (!videoID || videoID.length == 0) return nil;
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

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        DeArrowEnabled: @YES,
        DeArrowReplaceTitles: @YES,
        DeArrowReplaceThumbnails: @YES,
        DeArrowFallbackToOriginal: @YES
    }];
}
