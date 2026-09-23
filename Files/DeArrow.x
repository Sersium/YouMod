#import "Headers.h"

// DeArrow Integration for YouTube iOS (YouMod)
// API: https://sponsor.ajay.app/api/branding?videoID={videoID}
// Thumbnails: https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID={videoID}&time={timestamp}

static NSString * const kYMDeArrowUpdatedNotification = @"YouModDeArrowUpdatedNotification";
static NSString *currentInlinePreviewVideoID = nil;

static NSString *YouModFindVideoIDFromView(UIView *view);

@interface ASTextNode (YouMod)
- (void)setNeedsDisplay;
- (UIView *)view;
@end

@interface YouModDeArrowManager : NSObject
@property (nonatomic, strong) NSCache<NSString *, NSDictionary *> *brandingCache;
@property (nonatomic, strong) NSCache<NSString *, NSString *> *titleToVideoIDCache;
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
    NSMutableDictionary *entry = (NSMutableDictionary *)[_brandingCache objectForKey:videoID];
    if (!entry) {
        entry = [NSMutableDictionary dictionary];
        entry[@"videoID"] = videoID;
        entry[@"originalTitle"] = [title copy];
        [_brandingCache setObject:entry forKey:videoID];
    } else if (!entry[@"originalTitle"]) {
        entry[@"originalTitle"] = [title copy];
    }
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
    if (cached && (cached[@"title"] != nil || cached[@"thumbnailURL"] != nil)) {
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

        NSDictionary *existing = [self.brandingCache objectForKey:videoID];
        NSMutableDictionary *branding = existing ? [existing mutableCopy] : [NSMutableDictionary dictionary];
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

        NSString *candidateURL = nil;
        if (bestTimestamp) {
            candidateURL = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@&time=%@", videoID, bestTimestamp];
            branding[@"timestamp"] = bestTimestamp;
        } else {
            candidateURL = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@", videoID];
        }
        branding[@"thumbnailURL"] = candidateURL;
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
    if (!deArrowThumb) {
        deArrowThumb = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@", videoID];
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

    // Propagate videoID to parent nodes and sibling subnodes
    ASDisplayNode *cur = self.supernode;
    while (cur) {
        objc_setAssociatedObject(cur, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([cur respondsToSelector:@selector(subnodes)]) {
            for (ASDisplayNode *child in cur.subnodes) {
                objc_setAssociatedObject(child, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if ([child isKindOfClass:%c(ASTextNode)]) {
                    ASTextNode *tn = (ASTextNode *)child;
                    NSString *curStr = tn.attributedText.string;
                    if (curStr.length > 4 && !objc_getAssociatedObject(tn, "kYMDeArrowOrigAttrKey")) {
                        BOOL isMeta = ([curStr containsString:@" views"] || [curStr containsString:@" watching"] || [curStr containsString:@" ago"] || [curStr containsString:@" • "]);
                        if (!isMeta) {
                            objc_setAssociatedObject(tn, "kYMDeArrowOrigAttrKey", tn.attributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                            [[YouModDeArrowManager sharedInstance] registerOriginalTitle:curStr forVideoID:videoID];
                            NSString *deTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
                            if (deTitle.length > 0 && ![curStr isEqualToString:deTitle]) {
                                NSMutableAttributedString *mod = [[NSMutableAttributedString alloc] initWithAttributedString:tn.attributedText];
                                [mod.mutableString setString:deTitle];
                                [tn setAttributedText:mod];
                            }
                        }
                    }
                }
            }
        }
        cur = cur.supernode;
    }

    if ([self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if (v) {
            objc_setAssociatedObject(v, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIView *p = v.superview;
            while (p) {
                objc_setAssociatedObject(p, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                p = p.superview;
            }
        }
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
    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (videoID && [self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if (v) objc_setAssociatedObject(v, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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

    NSString *curStr = attributedString.string;
    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!videoID) {
        ASDisplayNode *cur = self.supernode;
        while (cur && !videoID) {
            videoID = objc_getAssociatedObject(cur, "kYMDeArrowVideoIDKey");
            cur = cur.supernode;
        }
    }
    if (!videoID) {
        videoID = [[YouModDeArrowManager sharedInstance] videoIDForTitle:curStr];
    }
    if (!videoID && [self respondsToSelector:@selector(view)]) {
        UIView *v = [self performSelector:@selector(view)];
        if (v && v.superview) {
            videoID = YouModFindVideoIDFromView(v.superview);
        }
    }

    if (videoID && videoID.length == 11) {
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        BOOL isMetadata = ([curStr containsString:@" views"] || [curStr containsString:@" watching"] || [curStr containsString:@" ago"] || [curStr containsString:@" • "] || curStr.length < 4);

        if (!isMetadata) {
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
    if (!myVideoID && self.supernode) {
        ASDisplayNode *cur = self.supernode;
        while (cur && !myVideoID) {
            myVideoID = objc_getAssociatedObject(cur, "kYMDeArrowVideoIDKey");
            cur = cur.supernode;
        }
        if (myVideoID) objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", myVideoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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
        if ([self respondsToSelector:@selector(view)]) {
            UIView *v = [self performSelector:@selector(view)];
            [v setNeedsDisplay];
            [v setNeedsLayout];
        }
    }
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

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIFontWeightMedium];
    UIImage *img = [UIImage systemImageNamed:@"dot.circle" withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"circle.circle.fill" withConfiguration:cfg];
    [indBtn setImage:img forState:UIControlStateNormal];

    if (isOriginal || !hasBranding) {
        indBtn.tintColor = [UIColor colorWithWhite:0.55 alpha:0.6];
    } else {
        indBtn.tintColor = [UIColor colorWithRed:0.0 green:0.68 blue:1.0 alpha:1.0]; // DeArrow cyan/blue
    }
}

static void YouModCollectNodesFromView(UIView *view, NSMutableArray *textNodes, NSMutableArray *imageNodes) {
    if (!view) return;
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
        if ([node isKindOfClass:%c(ASTextNode)]) {
            [textNodes addObject:node];
        } else if ([node isKindOfClass:%c(ASNetworkImageNode)]) {
            [imageNodes addObject:node];
        }
    }
    for (UIView *sub in view.subviews) {
        YouModCollectNodesFromView(sub, textNodes, imageNodes);
    }
}

static ASTextNode *YouModFindTitleNode(NSArray *textNodes) {
    ASTextNode *bestNode = nil;
    NSUInteger maxLen = 0;
    for (id node in textNodes) {
        if (![node isKindOfClass:%c(ASTextNode)]) continue;
        ASTextNode *tn = (ASTextNode *)node;
        NSString *s = tn.attributedText.string;
        if (!s || s.length < 5) continue;
        if ([s containsString:@" views"] || [s containsString:@" watching"] || 
            [s containsString:@" ago"] || [s containsString:@" • "] ||
            [s hasPrefix:@"http"] || [s containsString:@"subscribers"]) {
            continue;
        }
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
        NSURL *u = nil;
        if ([inNode respondsToSelector:@selector(URL)]) {
            u = [inNode URL];
        }
        if (!u && [inNode respondsToSelector:@selector(imageURL)]) {
            u = [inNode imageURL];
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

    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] toggleDeArrowForVideoID:videoID];

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback prepare];
    [feedback impactOccurred];

    UIView *container = button.superview;
    if (container) {
        NSMutableArray *textNodes = [NSMutableArray array];
        NSMutableArray *imageNodes = [NSMutableArray array];
        YouModCollectNodesFromView(container, textNodes, imageNodes);

        ASTextNode *tn = YouModFindTitleNode(textNodes);
        if (tn) {
            NSAttributedString *origAttr = objc_getAssociatedObject(tn, "kYMDeArrowOrigAttrKey") ?: tn.attributedText;
            if (isOriginal) {
                [tn setAttributedText:origAttr];
            } else {
                NSString *deTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
                if (deTitle.length > 0) {
                    NSMutableAttributedString *mod = [[NSMutableAttributedString alloc] initWithAttributedString:origAttr];
                    [mod.mutableString setString:deTitle];
                    [tn setAttributedText:mod];
                }
            }
            [tn setNeedsDisplay];
            if ([tn respondsToSelector:@selector(view)]) {
                [[tn view] setNeedsDisplay];
            }
        }

        NSString *extractedVID = nil;
        ASNetworkImageNode *inNode = YouModFindThumbnailNode(imageNodes, &extractedVID);
        if (inNode) {
            if (isOriginal) {
                NSURL *origURL = objc_getAssociatedObject(inNode, "kYMDeArrowOrigURLKey");
                if (origURL) [inNode setURL:origURL resetToDefault:YES];
            } else {
                NSString *deThumb = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
                if (!deThumb) deThumb = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@", videoID];
                [inNode setURL:[NSURL URLWithString:deThumb] resetToDefault:YES];
            }
            [inNode setNeedsDisplay];
            if ([inNode respondsToSelector:@selector(view)]) {
                [[inNode view] setNeedsDisplay];
            }
        }
    }

    YouModUpdateOverflowIndicator(button, videoID);
}

@end

// Robust helper to extract video ID from an ASDisplayView or its hierarchy
static NSString *YouModFindVideoIDFromView(UIView *view) {
    if (!view) return nil;
    NSString *vID = objc_getAssociatedObject(view, "kYMDeArrowVideoIDKey");
    if (vID.length == 11) return vID;

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

    return YouModExtractDeArrowVideoID([view description]);
}

%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
        return;
    }
    if (!IS_ENABLED(DeArrowEnabled)) return;

    if (YouModIsOverflowButtonView(self)) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowNotification:) name:kYMDeArrowUpdatedNotification object:nil];
    }
}

- (void)layoutSubviews {
    %orig;
    if (!IS_ENABLED(DeArrowEnabled)) return;
    if (!YouModIsOverflowButtonView(self)) return;

    UIView *superv = self.superview;
    if (!superv) return;

    // Target container view: expand beyond narrow button wrapper if needed
    UIView *container = superv;
    if (container.frame.size.width < 50 && container.superview) {
        container = container.superview;
    }

    superv.clipsToBounds = NO;
    container.clipsToBounds = NO;

    NSMutableArray *textNodes = [NSMutableArray array];
    NSMutableArray *imageNodes = [NSMutableArray array];
    YouModCollectNodesFromView(container, textNodes, imageNodes);

    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!videoID) {
        NSString *extractedVID = nil;
        YouModFindThumbnailNode(imageNodes, &extractedVID);
        if (extractedVID.length == 11) videoID = extractedVID;
    }
    if (!videoID) {
        videoID = YouModFindVideoIDFromView(container);
    }
    if (!videoID || videoID.length != 11) return;

    objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(container, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIButton *indBtn = (UIButton *)[container viewWithTag:0xDEA222];
    if (!indBtn) {
        indBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        indBtn.tag = 0xDEA222;
        indBtn.userInteractionEnabled = YES;
        [indBtn addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        [container addSubview:indBtn];
    }

    objc_setAssociatedObject(indBtn, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGRect rectInContainer = [self convertRect:self.bounds toView:container];
    CGFloat btnSize = 22.0;
    CGFloat btnX = rectInContainer.origin.x - btnSize - 6.0;
    CGFloat btnY = rectInContainer.origin.y + (rectInContainer.size.height - btnSize) / 2.0;
    indBtn.frame = CGRectMake(btnX, btnY, btnSize, btnSize);

    YouModUpdateOverflowIndicator(indBtn, videoID);

    // Apply DeArrow to title node and thumbnail node if available
    ASTextNode *tn = YouModFindTitleNode(textNodes);
    if (tn) {
        objc_setAssociatedObject(tn, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!objc_getAssociatedObject(tn, "kYMDeArrowOrigAttrKey")) {
            objc_setAssociatedObject(tn, "kYMDeArrowOrigAttrKey", tn.attributedText, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [[YouModDeArrowManager sharedInstance] registerOriginalTitle:tn.attributedText.string forVideoID:videoID];
        }
        BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID];
        if (!isOriginal && IS_ENABLED(DeArrowReplaceTitles)) {
            NSString *deTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
            if (deTitle.length > 0 && ![tn.attributedText.string isEqualToString:deTitle]) {
                NSAttributedString *origAttr = objc_getAssociatedObject(tn, "kYMDeArrowOrigAttrKey") ?: tn.attributedText;
                NSMutableAttributedString *mod = [[NSMutableAttributedString alloc] initWithAttributedString:origAttr];
                [mod.mutableString setString:deTitle];
                [tn setAttributedText:mod];
                [tn setNeedsDisplay];
                if ([tn respondsToSelector:@selector(view)]) [[tn view] setNeedsDisplay];
            }
        }
    }

    NSString *extractedVID = nil;
    ASNetworkImageNode *inNode = YouModFindThumbnailNode(imageNodes, &extractedVID);
    if (inNode) {
        objc_setAssociatedObject(inNode, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!objc_getAssociatedObject(inNode, "kYMDeArrowOrigURLKey") && [inNode respondsToSelector:@selector(URL)]) {
            objc_setAssociatedObject(inNode, "kYMDeArrowOrigURLKey", [inNode URL], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID];
        if (!isOriginal && IS_ENABLED(DeArrowReplaceThumbnails)) {
            NSString *deThumb = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:videoID];
            if (deThumb.length > 0) {
                [inNode setURL:[NSURL URLWithString:deThumb] resetToDefault:YES];
                [inNode setNeedsDisplay];
                if ([inNode respondsToSelector:@selector(view)]) [[inNode view] setNeedsDisplay];
            }
        }
    }

    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
}

%new
- (void)youmod_onDeArrowNotification:(NSNotification *)notif {
    NSString *notifVideoID = notif.userInfo[@"videoID"];
    NSString *myVideoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (!myVideoID && self.superview) {
        myVideoID = YouModFindVideoIDFromView(self.superview);
        if (myVideoID) objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", myVideoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!myVideoID || ![myVideoID isEqualToString:notifVideoID]) return;

    UIView *superv = self.superview;
    UIView *container = superv;
    if (container.frame.size.width < 50 && container.superview) {
        container = container.superview;
    }
    if (!container) return;

    UIButton *indBtn = (UIButton *)[container viewWithTag:0xDEA222];
    if (indBtn) {
        YouModUpdateOverflowIndicator(indBtn, myVideoID);
    }

    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:myVideoID];
    if (isOriginal) return;

    NSMutableArray *textNodes = [NSMutableArray array];
    NSMutableArray *imageNodes = [NSMutableArray array];
    YouModCollectNodesFromView(container, textNodes, imageNodes);

    if (IS_ENABLED(DeArrowReplaceTitles)) {
        ASTextNode *tn = YouModFindTitleNode(textNodes);
        if (tn) {
            NSString *deTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:myVideoID];
            if (deTitle.length > 0 && ![tn.attributedText.string isEqualToString:deTitle]) {
                NSAttributedString *origAttr = objc_getAssociatedObject(tn, "kYMDeArrowOrigAttrKey") ?: tn.attributedText;
                NSMutableAttributedString *mod = [[NSMutableAttributedString alloc] initWithAttributedString:origAttr];
                [mod.mutableString setString:deTitle];
                [tn setAttributedText:mod];
                [tn setNeedsDisplay];
                if ([tn respondsToSelector:@selector(view)]) [[tn view] setNeedsDisplay];
            }
        }
    }

    if (IS_ENABLED(DeArrowReplaceThumbnails)) {
        NSString *extractedVID = nil;
        ASNetworkImageNode *inNode = YouModFindThumbnailNode(imageNodes, &extractedVID);
        if (inNode) {
            NSString *deThumb = [[YouModDeArrowManager sharedInstance] thumbnailURLForVideoID:myVideoID];
            if (deThumb.length > 0) {
                [inNode setURL:[NSURL URLWithString:deThumb] resetToDefault:YES];
                [inNode setNeedsDisplay];
                if ([inNode respondsToSelector:@selector(view)]) [[inNode view] setNeedsDisplay];
            }
        }
    }
}

%end

#pragma mark - Inline Muted Playback Tracking

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

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        DeArrowEnabled: @YES,
        DeArrowReplaceTitles: @YES,
        DeArrowReplaceThumbnails: @YES,
        DeArrowFallbackToOriginal: @YES
    }];
}
