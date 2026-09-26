#import "Headers.h"

// DeArrow Integration for YouTube iOS (YouMod)
// API: https://sponsor.ajay.app/api/branding?videoID={videoID}
// Thumbnails: https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID={videoID}&time={timestamp}

static NSString * const kYMDeArrowUpdatedNotification = @"YouModDeArrowUpdatedNotification";


@interface ELMImageNode : ASNetworkImageNode
@end

@interface ASTextNode (YouMod)
- (void)setNeedsDisplay;
- (UIView *)view;
@end

@interface YouModDeArrowButton : UIButton
@end

@implementation YouModDeArrowButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect hitBounds = CGRectInset(self.bounds, -9.0, -9.0);
    return CGRectContainsPoint(hitBounds, point);
}
@end

static BOOL YouModIsLikelyBadgeOrMetadata(NSString *str) {
    if (!str || str.length < 4) return YES;
    if ([str containsString:@" views"] || [str containsString:@" watching"] || 
        [str containsString:@" ago"] || [str containsString:@" • "] || 
        [str containsString:@"subscribers"]) {
        return YES;
    }
    static NSRegularExpression *timeRegex = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        timeRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\d+:\\d{2}(:\\d{2})?$" options:0 error:nil];
    });
    if ([timeRegex numberOfMatchesInString:str options:0 range:NSMakeRange(0, str.length)] > 0) {
        return YES;
    }
    NSString *trimmed = [str stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].uppercaseString;
    if ([trimmed isEqualToString:@"LIVE"] || [trimmed isEqualToString:@"SHORTS"] || 
        [trimmed isEqualToString:@"PREMIERE"] || [trimmed isEqualToString:@"NEW"] || 
        [trimmed isEqualToString:@"CC"] || [trimmed isEqualToString:@"HD"] || 
        [trimmed isEqualToString:@"4K"]) {
        return YES;
    }
    return NO;
}


@interface YouModDeArrowManager : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *brandingCache;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *titleToVideoIDCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
@property (nonatomic, strong) NSCache<NSString *, NSDate *> *requestDates;
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
- (void)registerOriginalTitle:(NSString *)title forVideoID:(NSString *)videoID;
- (NSString *)videoIDForTitle:(NSString *)title;
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
        _titleToVideoIDCache = [[NSCache alloc] init];
        _titleToVideoIDCache.countLimit = 1000;
        _inFlightRequests = [NSMutableSet set];
        _requestDates = [[NSCache alloc] init];
        _requestDates.countLimit = 500;
        _toggledOriginalVideoIDs = [NSMutableSet set];
    }
    return self;
}

static NSString *YouModFormatDeArrowTitle(NSString *origTitle) {
    if (!origTitle || origTitle.length == 0) return origTitle;

    NSUInteger upperCount = 0;
    NSUInteger letterCount = 0;
    for (NSUInteger i = 0; i < origTitle.length; i++) {
        unichar c = [origTitle characterAtIndex:i];
        if ([[NSCharacterSet letterCharacterSet] characterIsMember:c]) {
            letterCount++;
            if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c]) {
                upperCount++;
            }
        }
    }

    BOOL isMostlyUpper = (letterCount > 4 && ((double)upperCount / (double)letterCount) > 0.45);

    static NSSet *knownAcronyms = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        knownAcronyms = [NSSet setWithObjects:
            @"NASA", @"USA", @"UK", @"EU", @"UN", @"FBI", @"CIA", @"AI", @"GTA", @"PS5", @"PS4", @"PS3",
            @"PC", @"VR", @"AR", @"RPG", @"FPS", @"CEO", @"DIY", @"FAQ", @"HD", @"4K", @"8K", @"BMW",
            @"WWII", @"WWI", @"COVID", @"NFL", @"NBA", @"MLB", @"UFC", @"WWE", @"ASMR", @"POV", @"VLOG",
            @"LEGO", @"TV", @"OLED", @"QLED", @"LED", @"RAM", @"CPU", @"GPU", @"SSD", @"USB", @"API",
            @"OS", @"iOS", @"macOS", @"HTML", @"CSS", @"JS", @"VS", @"MRBEAST",
            @"ID", @"IQ", @"IP", @"DM", @"GF", @"BF", @"DJ", @"MC", @"OK", @"RIP", @"VIP", @"SOS", nil];
    });

    NSArray *words = [origTitle componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *cleanedWords = [NSMutableArray array];
    BOOL startOfSentence = YES;

    for (NSString *rawWord in words) {
        if (rawWord.length == 0) {
            [cleanedWords addObject:@""];
            continue;
        }

        NSCharacterSet *punctSet = [NSCharacterSet punctuationCharacterSet];
        NSString *stripped = [rawWord stringByTrimmingCharactersInSet:punctSet];
        NSString *upperStripped = [stripped uppercaseString];

        NSString *wordToUse = rawWord;

        if (isMostlyUpper || (stripped.length > 1 && [stripped isEqualToString:upperStripped])) {
            if ([knownAcronyms containsObject:upperStripped]) {
                wordToUse = [rawWord stringByReplacingOccurrencesOfString:stripped withString:upperStripped];
            } else if ([stripped.lowercaseString isEqualToString:@"i"]) {
                wordToUse = [rawWord stringByReplacingOccurrencesOfString:stripped withString:@"I"];
            } else if ([stripped.lowercaseString hasPrefix:@"i'"]) {
                NSString *tail = [stripped substringFromIndex:1];
                wordToUse = [rawWord stringByReplacingOccurrencesOfString:stripped withString:[@"I" stringByAppendingString:tail.lowercaseString]];
            } else {
                NSString *lower = stripped.lowercaseString;
                if (startOfSentence && lower.length > 0) {
                    NSString *capitalized = [lower stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[lower substringToIndex:1] uppercaseString]];
                    wordToUse = [rawWord stringByReplacingOccurrencesOfString:stripped withString:capitalized];
                } else {
                    wordToUse = [rawWord stringByReplacingOccurrencesOfString:stripped withString:lower];
                }
            }
        }

        [cleanedWords addObject:wordToUse];

        if ([rawWord hasSuffix:@"."] || [rawWord hasSuffix:@"!"] || [rawWord hasSuffix:@"?"] || [rawWord hasSuffix:@":"]) {
            startOfSentence = YES;
        } else if (stripped.length > 0) {
            startOfSentence = NO;
        }
    }

    NSString *result = [cleanedWords componentsJoinedByString:@" "];
    if (result.length > 0) {
        unichar firstChar = [result characterAtIndex:0];
        if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:firstChar]) {
            result = [result stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[[result substringToIndex:1] uppercaseString]];
        }
    }
    return result;
}

- (void)registerOriginalTitle:(NSString *)title forVideoID:(NSString *)videoID {
    if (!title || title.length == 0 || !videoID || videoID.length == 0) return;
    [_titleToVideoIDCache setObject:videoID forKey:title];
    NSMutableDictionary *entry = [[_brandingCache objectForKey:videoID] mutableCopy];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        entry[@"videoID"] = videoID;
        entry[@"originalTitle"] = [title copy];
    } else if (!entry[@"originalTitle"]) {
        entry[@"originalTitle"] = [title copy];
    }
    [_brandingCache setObject:[entry copy] forKey:videoID];
}

- (NSString *)videoIDForTitle:(NSString *)title {
    if (!title || title.length == 0) return nil;
    return [_titleToVideoIDCache objectForKey:title];
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
    if (entry[@"title"] != nil || entry[@"thumbnailURL"] != nil) return YES;
    NSString *orig = entry[@"originalTitle"];
    if (orig.length > 0) {
        NSString *fmt = YouModFormatDeArrowTitle(orig);
        if (![fmt isEqualToString:orig]) return YES;
    }
    return NO;
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
    NSDictionary *entry = [_brandingCache objectForKey:videoID];
    if ([self isOriginalToggledForVideoID:videoID]) {
        return entry[@"originalTitle"];
    }
    if (entry) {
        NSString *title = entry[@"title"];
        if (title.length > 0) return title;
        NSString *orig = entry[@"originalTitle"];
        if (orig.length > 0) {
            return YouModFormatDeArrowTitle(orig);
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
    if ([cached[@"fetched"] boolValue]) {
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

        NSDictionary *existing = [self.brandingCache objectForKey:videoID];
        NSMutableDictionary *branding = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        branding[@"videoID"] = videoID;
        branding[@"fetched"] = @YES;

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

        if (bestTimestamp) {
            NSString *candidateURL = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@&time=%@", videoID, bestTimestamp];
            branding[@"timestamp"] = bestTimestamp;
            branding[@"thumbnailURL"] = candidateURL;
        }
        [self.brandingCache setObject:[branding copy] forKey:videoID];

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

// Elements Image Downloader hook (Modern YouTube Feeds)
%hook ELMImageDownloader

- (id)downloadImageWithURL:(NSURL *)url targetSize:(CGSize)size callbackQueue:(id)queue downloadProgress:(id)progress completion:(void(^)(id imageContainer, NSError *error, id arg3, id arg4))completion {
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails) || !url) {
        return %orig;
    }
    NSString *urlStr = url.absoluteString;
    NSString *videoID = YouModExtractDeArrowVideoID(urlStr);
    if (!videoID || videoID.length != 11) {
        return %orig;
    }
    if ([[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
        return %orig;
    }

    NSString *deArrowThumb = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
    if (!deArrowThumb || deArrowThumb.length == 0) {
        [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
        return %orig;
    }
    NSURL *deArrowURL = [NSURL URLWithString:deArrowThumb];

    __block id origTask = nil;
    void (^wrappedCompletion)(id, NSError *, id, id) = ^(id imageContainer, NSError *error, id arg3, id arg4) {
        if (!error && imageContainer) {
            if (completion) completion(imageContainer, nil, arg3, arg4);
        } else {
            origTask = %orig(url, size, queue, progress, completion);
        }
    };
    return %orig(deArrowURL, size, queue, progress, wrappedCompletion);
}

- (UIImage *)cachedImageWithURL:(NSURL *)url {
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails) || !url) {
        return %orig;
    }
    NSString *urlStr = url.absoluteString;
    NSString *videoID = YouModExtractDeArrowVideoID(urlStr);
    if (!videoID || videoID.length != 11) {
        return %orig;
    }
    if ([[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
        return %orig;
    }
    NSString *deArrowThumb = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
    if (deArrowThumb) {
        UIImage *cached = %orig([NSURL URLWithString:deArrowThumb]);
        if (cached) return cached;
    }
    return %orig;
}

%end

// AsyncDisplayKit network image hook
%hook ASNetworkImageNode

- (void)setURL:(NSURL *)url resetToDefault:(BOOL)reset {
    NSURL *failed = objc_getAssociatedObject(self, "kYMDeArrowFailedURL");
    if (failed && [url isEqual:failed]) url = objc_getAssociatedObject(self, "kYMDeArrowOrigURLKey");
    if (!url || (!YouModExtractDeArrowVideoID(url.absoluteString) && ![url.host isEqualToString:@"dearrow-thumb.ajay.app"])) {
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "kYMDeArrowOrigURLKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails) || !url) {
        %orig(url, reset);
        return;
    }

    if ([self.URL isEqual:url]) return;
    NSString *urlStr = url.absoluteString;
    NSString *videoID = YouModExtractDeArrowVideoID(urlStr);
    if (!videoID || videoID.length != 11) {
        %orig(url, reset);
        return;
    }

    objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "kYMDeArrowOrigURLKey", url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if ([[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
        %orig(url, reset);
        return;
    }

    NSString *deArrowURL = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
    if (deArrowURL.length > 0 && ![failed.absoluteString isEqualToString:deArrowURL]) {
        %orig([NSURL URLWithString:deArrowURL], reset);
        return;
    }

    // Load original thumbnail first to completely avoid blank/grey images
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowImageNotification:) name:kYMDeArrowUpdatedNotification object:nil];
}

%new
- (void)youmod_onDeArrowImageNotification:(NSNotification *)note {
    NSString *notifVideoID = note.userInfo[@"videoID"];
    NSString *myVideoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!myVideoID || ![myVideoID isEqualToString:notifVideoID]) return;

    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:myVideoID];
    if (isOriginal) {
        NSURL *origURL = objc_getAssociatedObject(self, "kYMDeArrowOrigURLKey");
        if (origURL) {
            [self setURL:origURL resetToDefault:NO];
            [self setNeedsDisplay];
        }
    } else {
        NSString *deArrowURL = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:myVideoID];
        if (deArrowURL.length > 0) {
            [self setURL:[NSURL URLWithString:deArrowURL] resetToDefault:NO];
            [self setNeedsDisplay];
        }
    }
}

%end

// ELMImageNode is the actual downloader delegate in YouTube 21.38.2.
%hook ELMImageNode
- (void)imageNode:(ASNetworkImageNode *)node didFailWithError:(NSError *)error {
    NSURL *original = objc_getAssociatedObject(node, "kYMDeArrowOrigURLKey");
    if (original && [node.URL.host isEqualToString:@"dearrow-thumb.ajay.app"]) {
        objc_setAssociatedObject(node, "kYMDeArrowFailedURL", node.URL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [node setURL:original resetToDefault:NO];
        return;
    }
    %orig;
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

- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowYTImageNotification:) name:kYMDeArrowUpdatedNotification object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
    }
}

%new
- (void)youmod_onDeArrowYTImageNotification:(NSNotification *)note {
    NSString *notifVideoID = note.userInfo[@"videoID"];
    NSString *myVideoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!myVideoID || ![myVideoID isEqualToString:notifVideoID]) return;

    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:myVideoID];
    if (isOriginal) {
        NSURL *origURL = objc_getAssociatedObject(self, "kYMDeArrowOrigURLKey");
        if (origURL) {
            [self setImageWithURL:origURL];
            [self setNeedsDisplay];
        }
    } else {
        NSString *deArrowURL = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:myVideoID];
        if (deArrowURL.length > 0) {
            [self setImageWithURL:[NSURL URLWithString:deArrowURL]];
            [self setNeedsDisplay];
        }
    }
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

    NSString *cleanTitle = [origTitle stringWithFormattingRemoved];
    if (cleanTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:cleanTitle forVideoID:vID];
    }

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

    NSString *cleanTitle = [origHeadline stringWithFormattingRemoved];
    if (cleanTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:cleanTitle forVideoID:vID];
    }

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

    NSString *cleanTitle = [origTitle stringWithFormattingRemoved];
    if (cleanTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:cleanTitle forVideoID:vID];
    }

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

    NSString *cleanTitle = [origTitle stringWithFormattingRemoved];
    if (cleanTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:cleanTitle forVideoID:vID];
    }

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

    NSString *cleanTitle = [origTitle stringWithFormattingRemoved];
    if (cleanTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:cleanTitle forVideoID:vID];
    }

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

    NSString *cleanTitle = [origTitle stringWithFormattingRemoved];
    if (cleanTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:cleanTitle forVideoID:vID];
    }

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

    if (origTitle.length > 0) {
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:origTitle forVideoID:vID];
    }

    NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:vID];
    if (deArrowTitle.length > 0) {
        return deArrowTitle;
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:vID];
    return origTitle;
}
%end

#pragma mark - Elements and Texture ASTextNode Title Hook

%hook ASTextNode

- (void)setAttributedText:(NSAttributedString *)attributedString {
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles) || attributedString.length == 0) {
        %orig;
        return;
    }

    // Skip text nodes that belong to thumbnails (e.g. duration badges, CC overlays)
    ASDisplayNode *ancestor = self.supernode;
    while (ancestor) {
        if ([ancestor isKindOfClass:%c(ASNetworkImageNode)]) {
            %orig(attributedString);
            return;
        }
        ancestor = ancestor.supernode;
    }

    NSString *curStr = attributedString.string;
    if (YouModIsLikelyBadgeOrMetadata(curStr)) {
        %orig(attributedString);
        return;
    }

    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    NSAttributedString *previous = objc_getAssociatedObject(self, "kYMDeArrowOrigAttrKey");
    NSString *replacement = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
    if (videoID && ![curStr isEqualToString:previous.string] && ![curStr isEqualToString:replacement]) {
        videoID = nil;
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "kYMDeArrowOrigAttrKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!videoID) {
        videoID = [[YouModDeArrowManager sharedInstance] videoIDForTitle:curStr];
    }

    if (videoID && videoID.length == 11) {
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (!objc_getAssociatedObject(self, "kYMDeArrowOrigAttrKey")) {
            objc_setAssociatedObject(self, "kYMDeArrowOrigAttrKey", attributedString, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [[YouModDeArrowManager sharedInstance] registerOriginalTitle:curStr forVideoID:videoID];
        }

        NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
        if (deArrowTitle && deArrowTitle.length > 0 && ![curStr isEqualToString:deArrowTitle]) {
            NSMutableAttributedString *mod = [[NSMutableAttributedString alloc] initWithAttributedString:attributedString];
            [mod.mutableString setString:deArrowTitle];
            %orig(mod);
            return;
        } else if (!deArrowTitle) {
            [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
        }
    }
    %orig(attributedString);
}

- (void)didLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowTextNotification:) name:kYMDeArrowUpdatedNotification object:nil];
}

%new
- (void)youmod_onDeArrowTextNotification:(NSNotification *)note {
    NSString *notifVideoID = note.userInfo[@"videoID"];
    NSString *myVideoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!myVideoID || ![myVideoID isEqualToString:notifVideoID]) return;

    NSAttributedString *origAttr = objc_getAssociatedObject(self, "kYMDeArrowOrigAttrKey");
    if (!origAttr) return;

    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:myVideoID];
    NSString *title = isOriginal ? [[YouModDeArrowManager sharedInstance] originalTitleForVideoID:myVideoID] : [[YouModDeArrowManager sharedInstance] titleForVideoID:myVideoID];
    if (title && title.length > 0) {
        NSMutableAttributedString *mod = [[NSMutableAttributedString alloc] initWithAttributedString:origAttr];
        [mod.mutableString setString:title];
        [self setAttributedText:mod];
        [self setNeedsDisplay];
        [self setNeedsLayout];
    }
}
%end

#pragma mark - DeArrow Indicator (Web-Style) next to 3-dots Menu & Feed Quick Swap

static BOOL YouModIsOverflowButtonView(UIView *view) {
    if (!view) return NO;
    NSString *iden = view.accessibilityIdentifier;
    if ([iden isEqualToString:@"eml.overflow_button"] ||
        [iden isEqualToString:@"id.ui.video.action.menu"] ||
        [iden isEqualToString:@"overflow_button"] ||
        ([iden containsString:@"overflow"] && [iden containsString:@"button"]) ||
        [iden containsString:@"action.menu"]) {
        return YES;
    }
    NSString *label = view.accessibilityLabel.lowercaseString;
    if (label.length > 0 && ([label isEqualToString:@"action menu"] || [label isEqualToString:@"more actions"])) {
        return YES;
    }
    return NO;
}

static void YouModUpdateOverflowIndicator(UIButton *indBtn, NSString *videoID) {
    if (!indBtn || !videoID) return;
    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID];
    BOOL hasBranding = [[YouModDeArrowManager sharedInstance] hasDeArrowBrandingForVideoID:videoID];

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIFontWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"dot.circle" withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"circle.circle.fill" withConfiguration:cfg];
    [indBtn setImage:img forState:UIControlStateNormal];

    if (isOriginal || !hasBranding) {
        indBtn.tintColor = [UIColor colorWithWhite:0.6 alpha:0.7];
        indBtn.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
    } else {
        indBtn.tintColor = [UIColor colorWithRed:0.0 green:0.72 blue:1.0 alpha:1.0]; // DeArrow cyan
        indBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:1.0 alpha:0.15];
    }
}

static void YouModCollectCardNodes(ASDisplayNode *node, NSMutableArray *textNodes, NSMutableArray *imageNodes) {
    if (!node) return;
    if ([node isKindOfClass:%c(ASTextNode)]) [textNodes addObject:node];
    if ([node isKindOfClass:%c(ASNetworkImageNode)]) [imageNodes addObject:node];
    NSArray *children = node.yogaChildren.count ? node.yogaChildren : node.subnodes;
    for (ASDisplayNode *child in children) {
        YouModCollectCardNodes(child, textNodes, imageNodes);
    }
}

static void YouModCollectNodesFromView(UIView *view, NSMutableArray *textNodes, NSMutableArray *imageNodes) {
    if ([view respondsToSelector:@selector(keepalive_node)]) {
        ASDisplayNode *node = [(id)view keepalive_node];
        if (node) {
            YouModCollectCardNodes(node, textNodes, imageNodes);
            return;
        }
    }
    for (UIView *child in view.subviews) YouModCollectNodesFromView(child, textNodes, imageNodes);
}

static ASTextNode *YouModFindTitleNode(NSArray *textNodes) {
    ASTextNode *bestNode = nil;
    NSUInteger maxLen = 0;
    for (id node in textNodes) {
        if (![node isKindOfClass:%c(ASTextNode)]) continue;
        ASTextNode *tn = (ASTextNode *)node;

        // Skip nodes inside thumbnail hierarchy
        ASDisplayNode *ancestor = tn.supernode;
        BOOL isInsideThumb = NO;
        while (ancestor) {
            if ([ancestor isKindOfClass:%c(ASNetworkImageNode)]) {
                isInsideThumb = YES;
                break;
            }
            ancestor = ancestor.supernode;
        }
        if (isInsideThumb) continue;

        NSString *s = tn.attributedText.string;
        if (!s || s.length < 5) continue;
        if (YouModIsLikelyBadgeOrMetadata(s)) continue;

        if (s.length > maxLen) {
            maxLen = s.length;
            bestNode = tn;
        }
    }
    return bestNode;
}

static ASNetworkImageNode *YouModFindThumbnailNode(NSArray *imageNodes, NSString **outVideoID) {
    for (id node in imageNodes) {
        if (![node isKindOfClass:%c(ASNetworkImageNode)]) continue;
        ASNetworkImageNode *inNode = (ASNetworkImageNode *)node;
        NSString *knownID = objc_getAssociatedObject(inNode, "kYMDeArrowVideoIDKey");
        if (knownID.length == 11) {
            if (outVideoID) *outVideoID = knownID;
            return inNode;
        }
        NSURL *u = nil;
        if ([inNode respondsToSelector:@selector(URL)]) {
            u = [inNode URL];
        }
        if (!u && [inNode respondsToSelector:@selector(imageURL)]) {
            u = [(id)inNode imageURL];
        }
        if (u) {
            NSString *vid = YouModExtractDeArrowVideoID(u.absoluteString);
            if (vid.length == 11) {
                if (outVideoID) *outVideoID = vid;
                return inNode;
            }
        }
    }
    return nil;
}

@interface YouModDeArrowSwapHandler : NSObject
+ (instancetype)sharedHandler;
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

- (void)handleSwapButtonTap:(UIButton *)button {
    NSString *videoID = objc_getAssociatedObject(button, "kYMDeArrowVideoIDKey");
    if (!videoID || videoID.length == 0) return;

    [[YouModDeArrowManager sharedInstance] toggleDeArrowForVideoID:videoID];
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    // The notification updates the bound title and image; no second reload.
    YouModUpdateOverflowIndicator(button, videoID);
}

@end

// Keep the toggle in the menu column. This column is outside both the title
// and thumbnail in home, compact channel, and notification cards.
static CGRect YouModDeArrowButtonFrame(CGRect bounds, CGRect menu) {
    CGFloat size = 26.0;
    CGFloat x = CGRectGetMidX(menu) - size / 2.0;
    CGFloat y = CGRectGetMaxY(menu) + 10.0;
    CGRect frame = CGRectMake(x, y, size, size);
    return CGRectContainsRect(bounds, frame) ? frame : CGRectZero;
}

static UIView *YouModDeArrowCard(UIView *menu, NSMutableArray *texts, NSMutableArray *images, NSString **videoID) {
    // Stop at the collection cell; never scan another card or the entire feed.
    for (UIView *card = menu.superview; card; card = card.superview) {
        if ([card isKindOfClass:[UIScrollView class]]) break;
        [texts removeAllObjects];
        [images removeAllObjects];
        YouModCollectNodesFromView(card, texts, images);
        YouModFindThumbnailNode(images, videoID);
        if (*videoID) return card;
        if ([card isKindOfClass:[UICollectionViewCell class]]) break;
    }
    return nil;
}

%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
    UIButton *button = objc_getAssociatedObject(self, "kYMDeArrowButton");
    if (!self.window || !IS_ENABLED(DeArrowEnabled)) {
        [button removeFromSuperview];
        return;
    }
    if (YouModIsOverflowButtonView(self)) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowNotification:) name:kYMDeArrowUpdatedNotification object:nil];
        [self setNeedsLayout];
    }
}

- (void)layoutSubviews {
    %orig;
    UIButton *button = objc_getAssociatedObject(self, "kYMDeArrowButton");
    if (!self.window || !IS_ENABLED(DeArrowEnabled) || !YouModIsOverflowButtonView(self)) {
        [button removeFromSuperview];
        return;
    }
    NSMutableArray *texts = [NSMutableArray array];
    NSMutableArray *images = [NSMutableArray array];
    NSString *videoID = nil;
    UIView *card = YouModDeArrowCard(self, texts, images, &videoID);
    if (!card) {
        [button removeFromSuperview];
        return;
    }
    // A metadata wrapper may contain the image but be shorter than the row.
    CGRect menu = [self convertRect:self.bounds toView:card];
    CGRect frame = YouModDeArrowButtonFrame(card.bounds, menu);
    while (CGRectIsEmpty(frame) && card.superview && ![card isKindOfClass:[UICollectionViewCell class]] &&
           ![card.superview isKindOfClass:[UIScrollView class]]) {
        card = card.superview;
        menu = [self convertRect:self.bounds toView:card];
        frame = YouModDeArrowButtonFrame(card.bounds, menu);
    }
    if (CGRectIsEmpty(frame)) {
        [button removeFromSuperview];
        return;
    }
    if (!button) {
        button = [YouModDeArrowButton buttonWithType:UIButtonTypeCustom];
        button.layer.cornerRadius = 13;
        button.accessibilityLabel = @"Toggle DeArrow original title and thumbnail";
        [button addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(self, "kYMDeArrowButton", button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(button, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (button.superview != card) [card addSubview:button];
    if (!CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    YouModUpdateOverflowIndicator(button, videoID);

    ASTextNode *title = YouModFindTitleNode(texts);
    if (title) {
        NSString *oldID = objc_getAssociatedObject(title, "kYMDeArrowVideoIDKey");
        if (![oldID isEqualToString:videoID]) {
            objc_setAssociatedObject(title, "kYMDeArrowOrigAttrKey", title.attributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(title, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [[YouModDeArrowManager sharedInstance] registerOriginalTitle:title.attributedText.string forVideoID:videoID];
        }
        if (IS_ENABLED(DeArrowReplaceTitles)) {
            NSString *replacement = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
            if (replacement.length && ![title.attributedText.string isEqualToString:replacement]) {
                NSMutableAttributedString *text = [title.attributedText mutableCopy];
                [text.mutableString setString:replacement];
                title.attributedText = text;
            }
        }
    }
    // Image nodes handle branding notifications themselves. Never reload here.
    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
}

%new
- (void)youmod_onDeArrowNotification:(NSNotification *)note {
    if ([note.userInfo[@"videoID"] isEqual:objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey")]) {
        [self setNeedsLayout];
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
