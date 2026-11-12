#import "Headers.h"
#import <ImageIO/ImageIO.h>

// DeArrow Integration for YouTube iOS (YouMod)
// API: https://sponsor.ajay.app/api/branding?videoID={videoID}
// Thumbnails: https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID={videoID}&time={timestamp}

static NSString * const kYMDeArrowUpdatedNotification = @"YouModDeArrowUpdatedNotification";
static NSAttributedString *YouModBoundWatchTitle(id label, NSAttributedString *native);
static void YouModClearWatchTitle(id label);
static NSString *descriptionTitleStatus;


@interface ELMImageNode : ASNetworkImageNode
@end

@interface ASTextNode (YouMod)
- (void)setNeedsDisplay;
- (UIView *)view;
@end

@interface ASDisplayNode (YouModDeArrowGeometry)
- (CGRect)convertRect:(CGRect)rect toNode:(ASDisplayNode *)node;
- (ELMNodeController *)nodeController;
- (ASTextNode *)currentTextNode;
@end

@interface YouModDeArrowButton : UIButton
@property (nonatomic, weak) UIView *overflowView;
@property (nonatomic, strong) UIView *indicatorBackdrop;
@property (nonatomic) CGRect indicatorFrame;
@end

@implementation YouModDeArrowButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect hitBounds = CGRectInset(self.bounds, -MAX(0, (44 - self.bounds.size.width) / 2), -MAX(0, (44 - self.bounds.size.height) / 2));
    return CGRectContainsPoint(hitBounds, point);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.indicatorBackdrop) self.imageView.center = CGPointMake(CGRectGetMidX(self.indicatorFrame), CGRectGetMidY(self.indicatorFrame));
}
@end

// Copy text styling, never native inline-image or glyph-substitution runs.
static NSAttributedString *YouModDeArrowTitleText(NSAttributedString *original, NSString *title) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if (original.length) {
        NSDictionary *source = [original attributesAtIndex:0 effectiveRange:NULL];
        for (NSString *key in @[NSFontAttributeName, NSForegroundColorAttributeName, NSParagraphStyleAttributeName]) {
            if (source[key]) attributes[key] = source[key];
        }
    }
    return [[NSAttributedString alloc] initWithString:title attributes:attributes];
}

static NSString *YouModCleanDeArrowTitle(NSString *title) {
    if (![title isKindOfClass:NSString.class]) return nil;
    for (NSString *character in @[@"\uFFFC", @"\u200B", @"\uFEFF"]) {
        title = [title stringByReplacingOccurrencesOfString:character withString:@" "];
    }
    static NSRegularExpression *separator;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Remove a separator stuck to a word, preserving comparisons such as A > B.
        separator = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\S)>(?=\\S)" options:0 error:nil];
    });
    title = [separator stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@" "];
    NSArray *words = [title componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[words filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

static BOOL YouModIsGroupedUploadText(NSString *text) {
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"\\buploaded\\s+[0-9]+\\s+videos\\s*$" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return text.length && [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

static BOOL YouModIsLikelyBadgeOrMetadata(NSString *str) {
    if (!str || str.length < 4 || YouModIsGroupedUploadText(str)) return YES;
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
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnailCache;
@property (nonatomic, strong) NSMutableSet<NSString *> *thumbnailRequests;
@property (nonatomic, strong) NSCache<NSString *, NSDate *> *thumbnailRequestDates;
@property (nonatomic, strong) NSMutableSet<NSString *> *inFlightRequests;
@property (nonatomic, strong) NSCache<NSString *, NSDate *> *requestDates;
@property (nonatomic, strong) NSMutableSet<NSString *> *toggledOriginalVideoIDs;
+ (instancetype)sharedInstance;
- (void)fetchBrandingForVideoID:(NSString *)videoID completion:(void (^)(NSDictionary *branding))completion;
- (void)prefetchBrandingForVideoID:(NSString *)videoID;
- (UIImage *)thumbnailForVideoID:(NSString *)videoID;
- (NSString *)titleForVideoID:(NSString *)videoID;
- (NSString *)originalTitleForVideoID:(NSString *)videoID;
- (NSString *)thumbnailURLForVideoID:(NSString *)videoID;
- (BOOL)isOriginalToggledForVideoID:(NSString *)videoID;
- (BOOL)toggleDeArrowForVideoID:(NSString *)videoID;
- (BOOL)hasDeArrowBrandingForVideoID:(NSString *)videoID;
- (void)registerOriginalTitle:(NSString *)title forVideoID:(NSString *)videoID;
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
        _thumbnailCache = [[NSCache alloc] init];
        _thumbnailCache.totalCostLimit = 32 * 1024 * 1024;
        _thumbnailRequests = [NSMutableSet set];
        _thumbnailRequestDates = [[NSCache alloc] init];
        _thumbnailRequestDates.countLimit = 500;
        _inFlightRequests = [NSMutableSet set];
        _requestDates = [[NSCache alloc] init];
        _requestDates.countLimit = 500;
        _toggledOriginalVideoIDs = [NSMutableSet set];
    }
    return self;
}

static NSString *YouModFormatDeArrowTitle(NSString *origTitle) {
    origTitle = YouModCleanDeArrowTitle(origTitle);
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
    if (!title.length || !videoID.length || YouModIsGroupedUploadText(title)) return;
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

// Download independently of YouTube's ELM cache. Never send a replacement URL
// to its renderer: rejected/cancelled replacements must leave the original intact.
- (UIImage *)thumbnailForVideoID:(NSString *)videoID {
    NSString *url = [self thumbnailURLForVideoID:videoID];
    if (!url.length) {
        [self prefetchBrandingForVideoID:videoID];
        return nil;
    }
    UIImage *cached = [_thumbnailCache objectForKey:url];
    if (cached) return cached;
    @synchronized (_thumbnailRequests) {
        NSDate *last = [_thumbnailRequestDates objectForKey:url];
        if ([_thumbnailRequests containsObject:url] || (last && -last.timeIntervalSinceNow < 60)) return nil;
        [_thumbnailRequests addObject:url];
        [_thumbnailRequestDates setObject:NSDate.date forKey:url];
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.timeoutInterval = 20;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = nil;
        if (!error && [(NSHTTPURLResponse *)response statusCode] == 200 && data.length && data.length <= 8 * 1024 * 1024) {
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
            if (source) {
                NSDictionary *options = @{(id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                    (id)kCGImageSourceThumbnailMaxPixelSize: @1280,
                    (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
                    (id)kCGImageSourceShouldCacheImmediately: @YES};
                CGImageRef decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
                if (decoded) {
                    image = [UIImage imageWithCGImage:decoded];
                    [self.thumbnailCache setObject:image forKey:url cost:CGImageGetBytesPerRow(decoded) * CGImageGetHeight(decoded)];
                    CGImageRelease(decoded);
                }
                CFRelease(source);
            }
        }
        @synchronized (self.thumbnailRequests) { [self.thumbnailRequests removeObject:url]; }
        if (image) dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kYMDeArrowUpdatedNotification object:nil userInfo:@{@"videoID": videoID}];
        });
    }] resume];
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
                if (![tObj[@"title"] isKindOfClass:NSString.class]) continue;
                BOOL isOriginal = [tObj[@"original"] isKindOfClass:NSNumber.class] && [tObj[@"original"] boolValue];
                BOOL isLocked = [tObj[@"locked"] isKindOfClass:NSNumber.class] && [tObj[@"locked"] boolValue];
                NSInteger votes = [tObj[@"votes"] isKindOfClass:NSNumber.class] ? [tObj[@"votes"] integerValue] : 0;
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
                NSString *title = YouModCleanDeArrowTitle(bestTitleObj[@"title"]);
                if (title.length) branding[@"title"] = title;
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
                if (![tsVal isKindOfClass:NSNumber.class] || !isfinite([tsVal doubleValue]) || [tsVal doubleValue] < 0) continue;
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

        // The API supplies the generated fallback as a fraction of duration.
        if (!bestTimestamp && [json[@"randomTime"] isKindOfClass:NSNumber.class] &&
            [json[@"videoDuration"] isKindOfClass:NSNumber.class]) {
            double fraction = [json[@"randomTime"] doubleValue], duration = [json[@"videoDuration"] doubleValue];
            if (isfinite(fraction) && isfinite(duration) && fraction >= 0 && fraction <= 1 && duration > 0)
                bestTimestamp = @(fraction * duration);
        }
        if (bestTimestamp) {
            NSString *candidateURL = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@&time=%@", videoID, bestTimestamp];
            branding[@"timestamp"] = bestTimestamp;
            branding[@"thumbnailURL"] = candidateURL;
        } else {
            // Let the thumbnail service choose its official/generated frame when
            // branding has no duration; never guess a timestamp on the client.
            branding[@"thumbnailURL"] = [NSString stringWithFormat:@"https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=%@&officialTime=true", videoID];
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

void YouModDeArrowBeginWatchVideo(NSString *videoID) {
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
    if (IS_ENABLED(DeArrowEnabled) && IS_ENABLED(DeArrowReplaceTitles) && [manager isOriginalToggledForVideoID:videoID])
        [manager toggleDeArrowForVideoID:videoID];
}

static NSAttributedString *YouModOriginalTitleText(NSAttributedString *native, NSString *videoID) {
    NSString *original = [[YouModDeArrowManager sharedInstance] originalTitleForVideoID:videoID];
    return original.length && ![native.string isEqualToString:original] ? YouModDeArrowTitleText(native, original) : native;
}

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

// Legacy UIKit image views use their own layer; modern feeds use the draw hook below.
static void YouModUpdateThumbnailLayer(id owner, CALayer *host, NSString *videoID, BOOL visible) {
    CALayer *overlay = objc_getAssociatedObject(owner, "kYMDeArrowThumbnailLayer");
    UIImage *image = nil;
    if (visible && videoID.length == 11 && IS_ENABLED(DeArrowEnabled) && IS_ENABLED(DeArrowReplaceThumbnails) &&
        ![[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) {
        image = [[YouModDeArrowManager sharedInstance] thumbnailForVideoID:videoID];
    }
    if (!image || !host) {
        [overlay removeFromSuperlayer];
        overlay.contents = nil;
        return;
    }
    if (!overlay) {
        overlay = [CALayer layer];
        overlay.contentsGravity = kCAGravityResizeAspectFill;
        overlay.masksToBounds = YES;
        objc_setAssociatedObject(owner, "kYMDeArrowThumbnailLayer", overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(overlay.frame, host.bounds)) overlay.frame = host.bounds;
    if (overlay.cornerRadius != host.cornerRadius) overlay.cornerRadius = host.cornerRadius;
    if (overlay.contents != (__bridge id)image.CGImage) overlay.contents = (__bridge id)image.CGImage;
    // Keep native duration badges and other children above the replacement.
    if (overlay.superlayer != host) [host insertSublayer:overlay atIndex:0];
    [CATransaction commit];
}

// Drawing parameters are a fresh snapshot for each render. Substituting only
// its UIImage also covers flattened/rasterized home and notification cards.
// Neither the native URL nor the native downloaded image is ever replaced.
static void YouModRefreshThumbnailNode(ASNetworkImageNode *node) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ YouModRefreshThumbnailNode(node); });
        return;
    }
    NSString *videoID = YouModExtractDeArrowVideoID(node.URL.absoluteString);
    objc_setAssociatedObject(node, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (videoID.length == 11 && (node.interfaceState & 8)) {
        if (IS_ENABLED(DeArrowEnabled) && IS_ENABLED(DeArrowReplaceThumbnails))
            [[YouModDeArrowManager sharedInstance] thumbnailForVideoID:videoID];
        [node setNeedsDisplay];
    }
}

%hook ASNetworkImageNode
- (id)initWithCache:(id)cache downloader:(id)downloader {
    self = %orig;
    if (self) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowImageNotification:) name:kYMDeArrowUpdatedNotification object:nil];
    return self;
}
- (void)setURL:(NSURL *)url resetToDefault:(BOOL)reset {
    %orig(url, reset);
    // Read current identity on main, so an old completion cannot paint a reused card.
    // Logos self is unsafe-unretained; a fullscreen transition can destroy it
    // before this block runs. Resolve a zeroing weak reference on the main queue.
    __weak ASNetworkImageNode *weakNode = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ASNetworkImageNode *node = weakNode;
        if (node) YouModRefreshThumbnailNode(node);
    });
}
- (id)drawParametersForAsyncLayer:(id)layer {
    id parameters = %orig;
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceThumbnails)) return parameters;
    NSString *videoID = YouModExtractDeArrowVideoID(self.URL.absoluteString);
    if (!videoID.length || [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID]) return parameters;
    UIImage *replacement = [[YouModDeArrowManager sharedInstance] thumbnailForVideoID:videoID];
    // Verified in YouTube 21.38.2. A changed parameter class safely keeps the original.
    if (replacement && [parameters isKindOfClass:%c(ASImageNodeDrawParameters)]) {
        @try { [parameters setValue:replacement forKey:@"image"]; } @catch (id exception) {}
    }
    return parameters;
}
- (void)didEnterVisibleState {
    %orig;
    YouModRefreshThumbnailNode(self);
}
%new
- (void)youmod_onDeArrowImageNotification:(NSNotification *)note {
    if ([note.userInfo[@"videoID"] isEqual:YouModExtractDeArrowVideoID(self.URL.absoluteString)]) YouModRefreshThumbnailNode(self);
}
%end

%hook YTImageView
- (void)setImageWithURL:(NSURL *)url {
    objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", YouModExtractDeArrowVideoID(url.absoluteString), OBJC_ASSOCIATION_COPY_NONATOMIC);
    %orig(url);
    YouModUpdateThumbnailLayer(self, self.layer, objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey"), self.window != nil);
}
- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
    if (self.window) [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowYTImageNotification:) name:kYMDeArrowUpdatedNotification object:nil];
    YouModUpdateThumbnailLayer(self, self.layer, objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey"), self.window != nil);
}
- (void)layoutSubviews {
    %orig;
    YouModUpdateThumbnailLayer(self, self.layer, objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey"), self.window != nil);
}
%new
- (void)youmod_onDeArrowYTImageNotification:(NSNotification *)note {
    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if ([note.userInfo[@"videoID"] isEqual:videoID]) YouModUpdateThumbnailLayer(self, self.layer, videoID, self.window != nil);
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

- (void)didExitHierarchy {
    if (objc_getAssociatedObject(self, "YMDeArrowWatchLabelVideoID")) YouModClearWatchTitle(self);
    %orig;
}

- (void)setAttributedText:(NSAttributedString *)attributedString {
    if (objc_getAssociatedObject(self, "YMDeArrowWatchLabelVideoID")) {
        NSAttributedString *watchText = YouModBoundWatchTitle(self, attributedString);
        %orig(watchText);
        return;
    }
    if (!IS_ENABLED(DeArrowEnabled) || !IS_ENABLED(DeArrowReplaceTitles) || attributedString.length == 0) {
        %orig;
        return;
    }

    NSString *curStr = attributedString.string;
    NSString *videoID = objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey");
    if (videoID.length != 11) {
        %orig;
        return;
    }
    NSAttributedString *previous = objc_getAssociatedObject(self, "kYMDeArrowOrigAttrKey");
    NSString *replacement = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
    if (videoID && ![curStr isEqualToString:previous.string] && ![curStr isEqualToString:replacement]) {
        videoID = nil;
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, "kYMDeArrowOrigAttrKey", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!videoID) {
        %orig;
        return;
    }
    if (YouModIsLikelyBadgeOrMetadata(curStr)) {
        %orig(attributedString);
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

    if (videoID && videoID.length == 11) {
        objc_setAssociatedObject(self, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (!objc_getAssociatedObject(self, "kYMDeArrowOrigAttrKey")) {
            objc_setAssociatedObject(self, "kYMDeArrowOrigAttrKey", attributedString, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [[YouModDeArrowManager sharedInstance] registerOriginalTitle:curStr forVideoID:videoID];
        }

        NSString *deArrowTitle = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
        if (deArrowTitle && deArrowTitle.length > 0 && ![curStr isEqualToString:deArrowTitle]) {
            NSAttributedString *mod = YouModDeArrowTitleText(attributedString, deArrowTitle);
            %orig(mod);
            return;
        } else if (!deArrowTitle) {
            [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
        }
    }
    %orig(attributedString);
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
        NSAttributedString *mod = isOriginal ? origAttr : YouModDeArrowTitleText(origAttr, title);
        [self setAttributedText:mod];
        [self setNeedsDisplay];
        [self setNeedsLayout];
    }
}
%end

#pragma mark - DeArrow Indicator (Web-Style) next to 3-dots Menu & Feed Quick Swap

BOOL YouModIsOverflowButtonIdentifier(NSString *iden) {
    return [iden isEqualToString:@"eml.overflow_button"] ||
        [iden isEqualToString:@"id.ui.video.action.menu"] ||
        [iden isEqualToString:@"id.video.menu.button"] ||
        ([iden hasPrefix:@"id.ui.video."] && [iden hasSuffix:@".menu.button"]) ||
        [iden isEqualToString:@"overflow_button"] ||
        ([iden containsString:@"overflow"] && [iden containsString:@"button"]) ||
        [iden containsString:@"action.menu"];
}

BOOL YouModIsOverflowButtonView(UIView *view) {
    if (!view) return NO;
    if (YouModIsOverflowButtonIdentifier(view.accessibilityIdentifier)) return YES;
    NSString *label = view.accessibilityLabel.lowercaseString;
    if (label.length > 0 && ([label isEqualToString:@"action menu"] || [label isEqualToString:@"more actions"])) {
        return YES;
    }
    return NO;
}

static void YouModUpdateOverflowIndicator(UIButton *indBtn, NSString *videoID) {
    if (!indBtn || !videoID) return;
    BOOL isOriginal = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID];
    indBtn.accessibilityValue = isOriginal ? @"Original" : @"DeArrow";
    BOOL hasBranding = [[YouModDeArrowManager sharedInstance] hasDeArrowBrandingForVideoID:videoID];

    BOOL feed = [indBtn.accessibilityIdentifier isEqualToString:@"youmod.feed.dearrow"];
    static UIImage *image, *feedImage;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        image = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:cfg];
        feedImage = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightSemibold]];
    });
    UIImage *symbol = feed ? feedImage : image;
    if ([indBtn imageForState:UIControlStateNormal] != symbol) [indBtn setImage:symbol forState:UIControlStateNormal];

    if (isOriginal || !hasBranding) {
        indBtn.tintColor = [UIColor colorWithWhite:0.72 alpha:1.0];
        indBtn.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
    } else {
        indBtn.tintColor = [UIColor colorWithRed:0.0 green:0.72 blue:1.0 alpha:1.0]; // DeArrow cyan
        indBtn.backgroundColor = [UIColor colorWithRed:0.0 green:0.72 blue:1.0 alpha:0.15];
    }
    if (feed) {
        YouModDeArrowButton *button = (YouModDeArrowButton *)indBtn;
        if (!button.indicatorBackdrop) {
            button.indicatorBackdrop = [[UIView alloc] init];
            button.indicatorBackdrop.userInteractionEnabled = NO;
            [button insertSubview:button.indicatorBackdrop atIndex:0];
        }
        button.indicatorBackdrop.frame = button.indicatorFrame;
        button.indicatorBackdrop.layer.cornerRadius = button.indicatorFrame.size.width / 2;
        button.indicatorBackdrop.backgroundColor = button.backgroundColor;
        button.backgroundColor = UIColor.clearColor;
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
    // An aggregate notification has a channel heading, not a video title.
    for (ASTextNode *node in textNodes) {
        if (YouModIsGroupedUploadText(node.attributedText.string)) return nil;
    }
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
        CGSize size = inNode.bounds.size;
        if (size.width < 80 || size.height < 40 || size.width < size.height * 1.2) continue;
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
- (void)copyWatchTitleDetails:(UILongPressGestureRecognizer *)gesture;
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

- (void)copyWatchTitleDetails:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    NSString *details = objc_getAssociatedObject(gesture.view.superview, "YMWatchTitleStatus");
    details = details ?: @"YouMod: the watch title scan has not run for this action row.";
    UIPasteboard.generalPasteboard.string = [details stringByAppendingFormat:@"\nexpanded header: %@\n", descriptionTitleStatus ?: @"not rendered since launch"];
    [SBSkipNotificationView showSuccessInView:sbGetNotificationParent() message:LOC(@"COPIED_TO_CLIPBOARD") duration:3.0];
}

@end

// Use the native More column without changing any text measurement.
static CGRect YouModDeArrowButtonFrame(CGRect bounds, CGRect menu) {
    CGFloat x = MAX(CGRectGetMinX(bounds) + 2, MIN(CGRectGetMidX(menu) - 22, CGRectGetMaxX(bounds) - 46));
    CGRect frame = CGRectMake(x, CGRectGetMaxY(menu) + 12, 44, 44);
    return CGRectContainsRect(bounds, frame) ? frame : CGRectZero;
}

static CGRect YouModDeArrowIndicatorFrame(CGRect bounds, CGRect menu, CGRect target) {
    CGFloat size = MIN(32, MAX(26, menu.size.width - 4));
    CGFloat center = MAX(CGRectGetMinX(bounds) + size / 2 + 2, MIN(CGRectGetMidX(menu), CGRectGetMaxX(bounds) - size / 2 - 2));
    return CGRectMake(center - size / 2 - target.origin.x, (44 - size) / 2, size, size);
}

extern NSString *YouModCurrentWatchVideoID(void);
extern NSString *YouModCurrentWatchTitle(void);

void YouModUpdateWatchDeArrowButton(UIView *row, CGRect frame) {
    UIButton *button = objc_getAssociatedObject(row, "YMWatchDeArrowButton");
    NSString *videoID = YouModCurrentWatchVideoID();
    if (!row.window || !IS_ENABLED(DeArrowEnabled) || videoID.length != 11 || CGRectIsEmpty(frame)) {
        [button removeFromSuperview];
        return;
    }
    if (!button) {
        button = [YouModDeArrowButton buttonWithType:UIButtonTypeCustom];
        button.layer.cornerRadius = 13;
        button.accessibilityIdentifier = @"youmod.watch.dearrow";
        button.accessibilityLabel = @"Toggle DeArrow original title";
        button.accessibilityHint = @"Long press to copy troubleshooting details";
        [button addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        [button addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(copyWatchTitleDetails:)]];
        objc_setAssociatedObject(row, "YMWatchDeArrowButton", button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(button, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (button.superview != row) [row addSubview:button];
    if (!CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    if (row.subviews.lastObject != button) [row bringSubviewToFront:button];
    YouModUpdateOverflowIndicator(button, videoID);
    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
}

@interface YTSlimVideoInformationCell : UICollectionViewCell
@property (nonatomic, readonly) id titleLabel;
@property (nonatomic, readonly) UIView *experimentalTitleLabel;
@end
@interface YTSlimVideoInformationCellController : NSObject
@property (nonatomic, readonly) YTSlimVideoInformationCell *cell;
@property (nonatomic, readonly) NSString *videoID;
@end

static NSAttributedString *YouModReadTitleText(id label) {
    NSAttributedString *native = [label attributedText];
    if (!native.length && [label isKindOfClass:UILabel.class]) {
        UILabel *uiLabel = label;
        if (uiLabel.text.length) {
            NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
            if (uiLabel.font) attributes[NSFontAttributeName] = uiLabel.font;
            if (uiLabel.textColor) attributes[NSForegroundColorAttributeName] = uiLabel.textColor;
            native = [[NSAttributedString alloc] initWithString:uiLabel.text attributes:attributes];
        }
    }
    return native;
}

static NSAttributedString *YouModWatchTitleValue(id label, NSString *videoID, NSAttributedString *native) {
    if (!native.length) return native;
    NSString *oldID = objc_getAssociatedObject(label, "YMDeArrowWatchLabelVideoID");
    NSAttributedString *rendered = objc_getAssociatedObject(label, "YMDeArrowRenderedWatchTitle");
    if (![oldID isEqualToString:videoID] || (rendered && ![native isEqualToAttributedString:rendered])) {
        NSAttributedString *original = YouModOriginalTitleText(native, videoID);
        objc_setAssociatedObject(label, "YMDeArrowWatchOriginalTitle", original, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(label, "YMDeArrowWatchLabelVideoID", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [[YouModDeArrowManager sharedInstance] registerOriginalTitle:original.string forVideoID:videoID];
    }
    NSAttributedString *original = objc_getAssociatedObject(label, "YMDeArrowWatchOriginalTitle");
    BOOL enabled = IS_ENABLED(DeArrowEnabled) && IS_ENABLED(DeArrowReplaceTitles) &&
        ![[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID];
    NSString *replacement = enabled ? [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID] : nil;
    NSAttributedString *value = replacement.length ? YouModDeArrowTitleText(original, replacement) : original;
    objc_setAssociatedObject(label, "YMDeArrowRenderedWatchTitle", value, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return value;
}

static BOOL YouModWatchTitleMatches(id label, NSAttributedString *native, NSString *videoID) {
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
    if ([objc_getAssociatedObject(label, "YMDeArrowWatchLabelVideoID") isEqualToString:videoID] &&
        [native.string isEqualToString:[objc_getAssociatedObject(label, "YMDeArrowRenderedWatchTitle") string]]) return YES;
    NSString *text = YouModCleanDeArrowTitle(native.string);
    return text.length && ([text isEqualToString:YouModCleanDeArrowTitle([manager originalTitleForVideoID:videoID])] ||
        [text isEqualToString:YouModCleanDeArrowTitle([manager titleForVideoID:videoID])]);
}

static NSAttributedString *YouModBoundWatchTitle(id label, NSAttributedString *native) {
    NSString *videoID = objc_getAssociatedObject(label, "YMDeArrowWatchLabelVideoID");
    if (![videoID isEqualToString:YouModCurrentWatchVideoID()] || !YouModWatchTitleMatches(label, native, videoID)) {
        YouModClearWatchTitle(label);
        return native;
    }
    return YouModWatchTitleValue(label, videoID, native);
}

static void YouModClearWatchTitle(id label) {
    objc_setAssociatedObject(label, "YMDeArrowWatchLabelVideoID", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, "YMDeArrowWatchOriginalTitle", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(label, "YMDeArrowRenderedWatchTitle", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YouModUpdateWatchTitleLabel(id label, NSString *videoID) {
    NSAttributedString *native = YouModReadTitleText(label);
    NSAttributedString *value = YouModWatchTitleValue(label, videoID, native);
    if (value && ![native isEqualToAttributedString:value]) [label setAttributedText:value];
}

%hook UILabel
- (void)didMoveToWindow {
    if (!self.window && objc_getAssociatedObject(self, "YMDeArrowWatchLabelVideoID")) YouModClearWatchTitle(self);
    %orig;
}
- (void)setAttributedText:(NSAttributedString *)text {
    if (objc_getAssociatedObject(self, "YMDeArrowWatchLabelVideoID")) {
        NSAttributedString *value = YouModBoundWatchTitle(self, text);
        %orig(value);
        return;
    }
    %orig;
}
- (void)setText:(NSString *)text {
    if (text.length && objc_getAssociatedObject(self, "YMDeArrowWatchLabelVideoID")) {
        NSAttributedString *native = YouModDeArrowTitleText(YouModReadTitleText(self), text);
        NSAttributedString *value = YouModBoundWatchTitle(self, native);
        if (![text isEqualToString:value.string]) {
            self.attributedText = value;
            return;
        }
    }
    %orig;
}
%end

static void YouModUpdateWatchTitle(YTSlimVideoInformationCell *cell) {
    NSString *videoID = objc_getAssociatedObject(cell, "YMWatchTitleVideoID");
    BOOL hasRendererID = videoID.length == 11;
    // Native title controllers do not always populate their optional videoID.
    if (!videoID.length) videoID = YouModCurrentWatchVideoID();
    if (!cell.window || videoID.length != 11) return;
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
    if (!hasRendererID && ![manager originalTitleForVideoID:videoID].length) {
        NSString *nativeTitle = YouModCurrentWatchTitle();
        if (!nativeTitle.length) return;
        [manager registerOriginalTitle:nativeTitle forVideoID:videoID];
    }
    NSMutableArray *texts = [NSMutableArray array], *images = [NSMutableArray array];
    id experimental = cell.experimentalTitleLabel;
    if (experimental && ![experimental respondsToSelector:@selector(attributedText)]) YouModCollectNodesFromView(experimental, texts, images);
    NSMutableArray *labels = [texts mutableCopy];
    if ([experimental respondsToSelector:@selector(attributedText)]) [labels addObject:experimental];
    if ([cell.titleLabel respondsToSelector:@selector(attributedText)] && cell.titleLabel != experimental) [labels addObject:cell.titleLabel];
    for (id label in labels) {
        if (!hasRendererID) {
            NSString *text = [[label attributedText] string];
            BOOL bound = [objc_getAssociatedObject(label, "YMDeArrowWatchLabelVideoID") isEqualToString:videoID];
            if (!bound && ![text isEqualToString:[manager originalTitleForVideoID:videoID]] &&
                ![text isEqualToString:[manager titleForVideoID:videoID]]) continue;
        }
        YouModUpdateWatchTitleLabel(label, videoID);
    }
    if (IS_ENABLED(DeArrowEnabled)) [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
}

%hook YTSlimVideoInformationCellController
- (void)setCell:(YTSlimVideoInformationCell *)cell {
    %orig;
    if (!cell) return;
    objc_setAssociatedObject(cell, "YMWatchTitleVideoID", self.videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    YouModUpdateWatchTitle(cell);
}
- (void)setVideoID:(NSString *)videoID {
    %orig;
    if (!self.cell) return;
    objc_setAssociatedObject(self.cell, "YMWatchTitleVideoID", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    YouModUpdateWatchTitle(self.cell);
}
%end

%hook YTSlimVideoInformationCell
- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"YouModWatchStatsChanged" object:nil];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_watchTitleChanged:) name:kYMDeArrowUpdatedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_watchTitleChanged:) name:@"YouModWatchStatsChanged" object:nil];
    }
    YouModUpdateWatchTitle(self);
}
- (void)layoutSubviews {
    %orig;
    YouModUpdateWatchTitle(self);
}
- (void)prepareForReuse {
    objc_setAssociatedObject(self, "YMWatchTitleVideoID", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%new
- (void)youmod_watchTitleChanged:(NSNotification *)note {
    NSString *videoID = objc_getAssociatedObject(self, "YMWatchTitleVideoID") ?: YouModCurrentWatchVideoID();
    if ([note.name isEqualToString:@"YouModWatchStatsChanged"] || [note.userInfo[@"videoID"] isEqual:videoID]) YouModUpdateWatchTitle(self);
}
%end

static void YouModCollectWatchLabels(UIView *view, NSMutableArray *labels) {
    if ([view isKindOfClass:%c(YTPlayerView)] || [view isKindOfClass:%c(YTMainAppPlayerOverlayView)]) return;
    if ([view respondsToSelector:@selector(attributedText)] && [view respondsToSelector:@selector(setAttributedText:)]) [labels addObject:view];
    for (UIView *child in view.subviews) YouModCollectWatchLabels(child, labels);
}

static void YouModApplyWatchTitles(UIView *row, NSString *videoID) {
    UIView *cell = row;
    while (cell && ![cell isKindOfClass:UICollectionViewCell.class]) cell = cell.superview;
    if (!cell) return;
    UIView *parent = cell.superview;
    while (parent && ![parent isKindOfClass:UICollectionView.class]) parent = parent.superview;
    NSMutableArray *cells = [NSMutableArray arrayWithObject:cell];
    if (parent) {
        NSHashTable *rows = objc_getAssociatedObject(parent, "YMWatchTitleRows");
        if (!rows) {
            rows = [NSHashTable weakObjectsHashTable];
            objc_setAssociatedObject(parent, "YMWatchTitleRows", rows, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [rows addObject:row];
        CGRect actions = [row convertRect:row.bounds toView:parent];
        for (UICollectionViewCell *candidate in ((UICollectionView *)parent).visibleCells) {
            if (candidate != cell && CGRectGetMaxY(candidate.frame) <= CGRectGetMinY(actions) + 1) [cells addObject:candidate];
        }
    }
    YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
    if (![manager originalTitleForVideoID:videoID].length) {
        NSString *original = YouModCurrentWatchTitle();
        if (original.length) [manager registerOriginalTitle:original forVideoID:videoID];
    }
    NSMutableString *status = [NSMutableString stringWithFormat:@"YouMod watch title\nvideo=%@\ntitles enabled=%d\noriginal=%@\nselected title=%@\nrow=%@\ncells=%lu\n", videoID,
        IS_ENABLED(DeArrowEnabled) && IS_ENABLED(DeArrowReplaceTitles), [manager originalTitleForVideoID:videoID] ?: @"(missing)",
        [manager titleForVideoID:videoID] ?: @"(missing)", NSStringFromClass(row.class), (unsigned long)cells.count];
    NSUInteger matches = 0;
    for (UIView *candidate in cells) {
        NSMutableArray *labels = [NSMutableArray array], *images = [NSMutableArray array];
        if ([candidate isKindOfClass:%c(_ASCollectionViewCell)]) {
            YouModCollectCardNodes(((_ASCollectionViewCell *)candidate).node, labels, images);
        } else {
            YouModCollectNodesFromView(candidate, labels, images);
        }
        YouModCollectWatchLabels(candidate, labels);
        if (status.length < 8000) [status appendFormat:@"cell=%@ y=%.0f labels=%lu\n", NSStringFromClass(candidate.class), candidate.frame.origin.y, (unsigned long)labels.count];
        for (id label in labels) {
            NSAttributedString *native = YouModReadTitleText(label);
            BOOL match = YouModWatchTitleMatches(label, native, videoID);
            if (status.length < 8000) [status appendFormat:@"%@ match=%d text=%@\n", NSStringFromClass([label class]), match,
                native.length > 160 ? [native.string substringToIndex:160] : native.string ?: @""];
            if (match) {
                matches++;
                YouModUpdateWatchTitleLabel(label, videoID);
            }
        }
    }
    [status appendFormat:@"matched titles=%lu\n", (unsigned long)matches];
    objc_setAssociatedObject(row, "YMWatchTitleStatus", status, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (IS_ENABLED(DeArrowEnabled)) [manager prefetchBrandingForVideoID:videoID];
}

void YouModUpdateWatchTitlesForRow(UIView *row) {
    NSString *videoID = YouModCurrentWatchVideoID();
    if (!row.window || videoID.length != 11 || objc_getAssociatedObject(row, "YMWatchTitleQueued")) return;
    objc_setAssociatedObject(row, "YMWatchTitleQueued", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakRow = row;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *currentRow = weakRow;
        if (!currentRow) return;
        objc_setAssociatedObject(currentRow, "YMWatchTitleQueued", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!currentRow.window) return;
        if ([videoID isEqualToString:YouModCurrentWatchVideoID()]) YouModApplyWatchTitles(currentRow, videoID);
        else YouModUpdateWatchTitlesForRow(currentRow);
    });
}

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    NSHashTable *rows = objc_getAssociatedObject(self, "YMWatchTitleRows");
    for (UIView *row in rows.allObjects) YouModUpdateWatchTitlesForRow(row);
}
%end

static void YouModCollectDescriptionLabels(ASDisplayNode *node, CGFloat y, NSMutableArray *labels, NSMutableArray *positions, NSHashTable *visited) {
    if (!node || [visited containsObject:node]) return;
    [visited addObject:node];
    if ([node isKindOfClass:%c(ASTextNode)]) {
        [labels addObject:node];
        [positions addObject:@(y)];
    }
    if (node.isNodeLoaded && !node.isLayerBacked) {
        UIView *view = node.view;
        NSMutableArray *views = [NSMutableArray array];
        YouModCollectWatchLabels(view, views);
        for (UIView *label in views) {
            if ([visited containsObject:label]) continue;
            [visited addObject:label];
            CGRect local = [label convertRect:label.bounds toView:view];
            [labels addObject:label];
            [positions addObject:@(y + CGRectGetMinY(local) - CGRectGetMinY(node.bounds))];
        }
    }
    // Yoga children and rendered subnodes can contain different text objects.
    for (ASDisplayNode *child in node.yogaChildren) YouModCollectDescriptionLabels(child, y + CGRectGetMinY(child.frame) - CGRectGetMinY(node.bounds), labels, positions, visited);
    for (ASDisplayNode *child in node.subnodes) YouModCollectDescriptionLabels(child, y + CGRectGetMinY(child.frame) - CGRectGetMinY(node.bounds), labels, positions, visited);
    if ([node respondsToSelector:@selector(currentTextNode)]) {
        ASDisplayNode *text = [node currentTextNode];
        if (text) YouModCollectDescriptionLabels(text, y + CGRectGetMinY(text.frame) - CGRectGetMinY(node.bounds), labels, positions, visited);
    }
}

static void YouModUpdateDescriptionTitle(ASDisplayNode *node) {
    if (!node || objc_getAssociatedObject(node, "YMDescriptionTitleQueued")) return;
    objc_setAssociatedObject(node, "YMDescriptionHeaderRoot", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(node, "YMDescriptionTitleQueued", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak ASDisplayNode *weakNode = node;
    // Native Elements callbacks can hold rendering locks; update text after they return.
    dispatch_async(dispatch_get_main_queue(), ^{
        ASDisplayNode *current = weakNode;
        if (!current) return;
        objc_setAssociatedObject(current, "YMDescriptionTitleQueued", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!objc_getAssociatedObject(current, "YMDescriptionObserved")) {
            [[NSNotificationCenter defaultCenter] addObserver:current selector:@selector(youmod_descriptionTitleChanged:) name:kYMDeArrowUpdatedNotification object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:current selector:@selector(youmod_descriptionTitleChanged:) name:@"YouModWatchStatsChanged" object:nil];
            objc_setAssociatedObject(current, "YMDescriptionObserved", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSString *videoID = YouModCurrentWatchVideoID();
        if (videoID.length != 11) return;
        YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
        if (![manager originalTitleForVideoID:videoID].length) [manager registerOriginalTitle:YouModCurrentWatchTitle() forVideoID:videoID];
        NSMutableArray *texts = [NSMutableArray array], *positions = [NSMutableArray array];
        NSHashTable *visited = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        YouModCollectDescriptionLabels(current, 0, texts, positions, visited);
        id title = nil;
        CGFloat top = CGFLOAT_MAX;
        NSMutableString *status = [NSMutableString stringWithFormat:@"video=%@ node=%@ texts=%lu", videoID,
            NSStringFromClass(current.class), (unsigned long)texts.count];
        for (NSUInteger i = 0; i < texts.count; i++) {
            id text = texts[i];
            NSAttributedString *native = YouModReadTitleText(text);
            BOOL match = YouModWatchTitleMatches(text, native, videoID);
            if (status.length < 8000) [status appendFormat:@"\n%@ match=%d text=%@", NSStringFromClass([text class]), match,
                native.length > 300 ? [native.string substringToIndex:300] : native.string ?: @"(empty)"];
            if (!match) continue;
            CGFloat y = [positions[i] doubleValue];
            // Choose the heading if native text is repeated farther down the header.
            if (!title || y < top) { title = text; top = y; }
        }
        if (title) {
            NSAttributedString *before = YouModReadTitleText(title);
            YouModUpdateWatchTitleLabel(title, videoID);
            if (![before isEqualToAttributedString:YouModReadTitleText(title)]) [current setNeedsLayout];
        }
        [status appendFormat:@"\nmatched=%d", title != nil];
        descriptionTitleStatus = status;
        if (IS_ENABLED(DeArrowEnabled)) [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
    });
}

static void YouModObserveDescriptionComponent(ELMComponent *component) {
    NSString *name = [[component.templateURI componentsSeparatedByString:@"|"].firstObject lastPathComponent];
    // The visible title and close button are separate from description metadata.
    if (![name hasPrefix:@"engagement_panel_header.eml"]) return;
    objc_setAssociatedObject(component, "YMDescriptionComponent", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!descriptionTitleStatus) descriptionTitleStatus = @"engagement header created; awaiting native node";
    });
}

%hook ELMComponent
- (id)initWithElement:(id)element context:(id)context treeLocalContext:(id)treeLocalContext {
    id component = %orig;
    YouModObserveDescriptionComponent(component);
    return component;
}
- (ASDisplayNode *)node {
    ASDisplayNode *node = %orig;
    // The native getter materializes the text controller lazily, after initialization.
    if (objc_getAssociatedObject(self, "YMDescriptionComponent")) YouModUpdateDescriptionTitle(node);
    return node;
}
%end

%hook ASDisplayNode
- (void)layout {
    %orig;
    if (objc_getAssociatedObject(self, "YMDescriptionHeaderRoot")) YouModUpdateDescriptionTitle(self);
}
%new
- (void)youmod_descriptionTitleChanged:(NSNotification *)note {
    if ([note.name isEqualToString:@"YouModWatchStatsChanged"] || [note.userInfo[@"videoID"] isEqualToString:YouModCurrentWatchVideoID()])
        YouModUpdateDescriptionTitle(self);
}
%end

@interface YTEngagementPanelIdentifier : NSObject
- (BOOL)equalToIdentifierString:(NSString *)identifier;
@end
@interface YTEngagementPanelHeaderView (YouModDeArrowTitle)
- (id)titleLabel;
- (YTEngagementPanelIdentifier *)engagementPanelIdentifier;
@end

static void YouModUpdateNativeDescriptionTitle(YTEngagementPanelHeaderView *header) {
    if (!header || objc_getAssociatedObject(header, "YMNativeDescriptionQueued")) return;
    objc_setAssociatedObject(header, "YMNativeDescriptionQueued", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak YTEngagementPanelHeaderView *weakHeader = header;
    dispatch_async(dispatch_get_main_queue(), ^{
        YTEngagementPanelHeaderView *current = weakHeader;
        if (!current) return;
        objc_setAssociatedObject(current, "YMNativeDescriptionQueued", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        id label = current.titleLabel;
        YTEngagementPanelIdentifier *identifier = current.engagementPanelIdentifier;
        BOOL description = [identifier equalToIdentifierString:@"engagement-panel-structured-description"] ||
            [identifier equalToIdentifierString:@"structured-description"];
        if (!current.window || !description) {
            [[NSNotificationCenter defaultCenter] removeObserver:current name:kYMDeArrowUpdatedNotification object:nil];
            [[NSNotificationCenter defaultCenter] removeObserver:current name:@"YouModWatchStatsChanged" object:nil];
            objc_setAssociatedObject(current, "YMNativeDescriptionObserved", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (label) YouModClearWatchTitle(label);
            return;
        }
        if (!objc_getAssociatedObject(current, "YMNativeDescriptionObserved")) {
            [[NSNotificationCenter defaultCenter] addObserver:current selector:@selector(youmod_nativeDescriptionTitleChanged:) name:kYMDeArrowUpdatedNotification object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:current selector:@selector(youmod_nativeDescriptionTitleChanged:) name:@"YouModWatchStatsChanged" object:nil];
            objc_setAssociatedObject(current, "YMNativeDescriptionObserved", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!label) return; // Hybrid headers render their title in engagement_panel_header.eml.
        NSString *videoID = YouModCurrentWatchVideoID();
        if (videoID.length != 11) return;
        YouModDeArrowManager *manager = [YouModDeArrowManager sharedInstance];
        if (![manager originalTitleForVideoID:videoID].length) [manager registerOriginalTitle:YouModCurrentWatchTitle() forVideoID:videoID];
        NSAttributedString *before = YouModReadTitleText(label);
        BOOL match = YouModWatchTitleMatches(label, before, videoID);
        if (match) {
            YouModUpdateWatchTitleLabel(label, videoID);
            if (![before isEqualToAttributedString:YouModReadTitleText(label)]) [current setNeedsLayout];
        }
        descriptionTitleStatus = [NSString stringWithFormat:@"video=%@ native header=%@ title=%@ matched=%d", videoID,
            NSStringFromClass(current.class), before.string ?: @"(empty)", match];
        if (IS_ENABLED(DeArrowEnabled)) [manager prefetchBrandingForVideoID:videoID];
    });
}

%hook YTEngagementPanelHeaderView
- (void)didMoveToWindow {
    %orig;
    YouModUpdateNativeDescriptionTitle(self);
}
- (void)layoutSubviews {
    %orig;
    YouModUpdateNativeDescriptionTitle(self);
}
- (void)setTitle:(id)title {
    %orig;
    YouModUpdateNativeDescriptionTitle(self);
}
- (void)setTitle:(id)title fontAttributes:(id)attributes {
    %orig;
    YouModUpdateNativeDescriptionTitle(self);
}
%new
- (void)youmod_nativeDescriptionTitleChanged:(NSNotification *)note {
    if ([note.name isEqualToString:@"YouModWatchStatsChanged"] || [note.userInfo[@"videoID"] isEqualToString:YouModCurrentWatchVideoID()])
        YouModUpdateNativeDescriptionTitle(self);
}
%end

UIView *YouModVideoCard(UIView *menu, NSMutableArray *texts, NSMutableArray *images, NSString **videoID) {
    // Establish a feed-cell boundary before touching Texture nodes. Player
    // overflow controls also match the menu identifiers, including mid-transition.
    UIView *cell = menu;
    while (cell) {
        if ([cell.accessibilityIdentifier.lowercaseString containsString:@"comment"]) return nil;
        if ([cell isKindOfClass:%c(YTPlayerView)] ||
            [cell isKindOfClass:%c(YTMainAppPlayerOverlayView)] ||
            [cell isKindOfClass:[UIScrollView class]]) return nil;
        if ([cell isKindOfClass:[UICollectionViewCell class]]) break;
        cell = cell.superview;
    }
    if (!cell) return nil;

    // Stop at the verified cell; never scan the player or the entire feed.
    for (UIView *card = menu.superview; card; card = card.superview) {
        [texts removeAllObjects];
        [images removeAllObjects];
        YouModCollectNodesFromView(card, texts, images);
        for (ASTextNode *text in texts) {
            if ([text.accessibilityIdentifier containsString:@"id.comment."] || YouModIsGroupedUploadText(text.attributedText.string)) return nil;
        }
        YouModFindThumbnailNode(images, videoID);
        if (*videoID) return card;
        if (card == cell) break;
    }
    return nil;
}

static void YouModApplyFeedDeArrow(UIView *menuView) {
    YouModDeArrowButton *button = objc_getAssociatedObject(menuView, "kYMDeArrowButton");
    if (!menuView.window || !IS_ENABLED(DeArrowEnabled) || !YouModIsOverflowButtonView(menuView)) {
        [button removeFromSuperview];
        return;
    }
    NSMutableArray *texts = [NSMutableArray array];
    NSMutableArray *images = [NSMutableArray array];
    NSString *videoID = nil;
    UIView *card = YouModVideoCard(menuView, texts, images, &videoID);
    if (!card || videoID.length != 11) {
        [button removeFromSuperview];
        return;
    }
    // A short metadata wrapper is not the cell's final height.
    while (![card isKindOfClass:UICollectionViewCell.class] && card.superview &&
           ![card.superview isKindOfClass:UIScrollView.class]) card = card.superview;
    NSHashTable *menus = objc_getAssociatedObject(card, "YMDeArrowFeedMenus");
    if (!menus) {
        menus = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(card, "YMDeArrowFeedMenus", menus, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [menus addObject:menuView];
    CGRect menu = [menuView convertRect:menuView.bounds toView:card];
    CGRect frame = YouModDeArrowButtonFrame(card.bounds, menu);
    if (CGRectIsEmpty(frame)) {
        [button removeFromSuperview];
        return;
    }
    if (!button) {
        button = [YouModDeArrowButton buttonWithType:UIButtonTypeCustom];
        button.layer.cornerRadius = 22;
        button.accessibilityIdentifier = @"youmod.feed.dearrow";
        button.accessibilityLabel = @"Toggle DeArrow original title and thumbnail";
        [button addTarget:[YouModDeArrowSwapHandler sharedHandler] action:@selector(handleSwapButtonTap:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(menuView, "kYMDeArrowButton", button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(menuView, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(button, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
    button.overflowView = menuView;
    if (button.superview != card) [card addSubview:button];
    if (!CGRectEqualToRect(button.frame, frame)) button.frame = frame;
    CGRect indicator = YouModDeArrowIndicatorFrame(card.bounds, menu, frame);
    if (!CGRectEqualToRect(button.indicatorFrame, indicator)) {
        button.indicatorFrame = indicator;
        [button setNeedsLayout];
    }
    if (card.subviews.lastObject != button) [card bringSubviewToFront:button];
    YouModUpdateOverflowIndicator(button, videoID);

    ASTextNode *title = YouModFindTitleNode(texts);
    if (title) {
        NSString *oldID = objc_getAssociatedObject(title, "kYMDeArrowVideoIDKey");
        if (![oldID isEqualToString:videoID]) {
            NSAttributedString *original = YouModOriginalTitleText(title.attributedText, videoID);
            objc_setAssociatedObject(title, "kYMDeArrowOrigAttrKey", original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(title, "kYMDeArrowVideoIDKey", videoID, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [[NSNotificationCenter defaultCenter] removeObserver:title name:kYMDeArrowUpdatedNotification object:nil];
            [[NSNotificationCenter defaultCenter] addObserver:title selector:@selector(youmod_onDeArrowTextNotification:) name:kYMDeArrowUpdatedNotification object:nil];
            [[YouModDeArrowManager sharedInstance] registerOriginalTitle:original.string forVideoID:videoID];
        }
        if (IS_ENABLED(DeArrowReplaceTitles)) {
            NSString *replacement = [[YouModDeArrowManager sharedInstance] titleForVideoID:videoID];
            if (replacement.length && ![title.attributedText.string isEqualToString:replacement]) {
                NSAttributedString *original = objc_getAssociatedObject(title, "kYMDeArrowOrigAttrKey");
                title.attributedText = [[YouModDeArrowManager sharedInstance] isOriginalToggledForVideoID:videoID] ? original : YouModDeArrowTitleText(original, replacement);
            }
        }
    }
    // Image nodes handle branding notifications themselves. Never reload here.
    [[YouModDeArrowManager sharedInstance] prefetchBrandingForVideoID:videoID];
}

static void YouModUpdateFeedDeArrow(UIView *menu) {
    if ((!YouModIsOverflowButtonView(menu) && !objc_getAssociatedObject(menu, "kYMDeArrowButton")) ||
        objc_getAssociatedObject(menu, "YMFeedDeArrowQueued")) return;
    objc_setAssociatedObject(menu, "YMFeedDeArrowQueued", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakMenu = menu;
    // Updating a Texture accessory inside native layout can keep the collection relaying out.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *current = weakMenu;
        if (!current) return;
        objc_setAssociatedObject(current, "YMFeedDeArrowQueued", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        YouModApplyFeedDeArrow(current);
    });
}

%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMDeArrowUpdatedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"YouModWatchStatsChanged" object:nil];
    UIButton *button = objc_getAssociatedObject(self, "kYMDeArrowButton");
    if (!self.window || !IS_ENABLED(DeArrowEnabled)) {
        [button removeFromSuperview];
        return;
    }
    if (YouModIsOverflowButtonView(self)) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowNotification:) name:kYMDeArrowUpdatedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDeArrowNotification:) name:@"YouModWatchStatsChanged" object:nil];
        YouModUpdateFeedDeArrow(self);
    }
}

- (void)layoutSubviews {
    %orig;
    YouModUpdateFeedDeArrow(self);
}

%new
- (void)youmod_onDeArrowNotification:(NSNotification *)note {
    UIButton *button = objc_getAssociatedObject(self, "kYMDeArrowButton");
    if (!button.superview || [note.name isEqualToString:@"YouModWatchStatsChanged"] || [note.userInfo[@"videoID"] isEqual:objc_getAssociatedObject(self, "kYMDeArrowVideoIDKey")]) {
        // Retry cards whose thumbnail identity was not ready on first layout.
        YouModUpdateFeedDeArrow(self);
    }
}
%end

@interface _ASCollectionViewCell (YouModDeArrowHitTesting)
- (BOOL)isAnimating;
@end

%hook _ASCollectionViewCell
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (IS_ENABLED(DeArrowEnabled) && self.userInteractionEnabled && !self.hidden && self.alpha > 0.01 && ![self isAnimating]) {
        NSHashTable *menus = objc_getAssociatedObject(self, "YMDeArrowFeedMenus");
        for (UIView *menu in menus.allObjects) {
            UIButton *button = objc_getAssociatedObject(menu, "kYMDeArrowButton");
            if (button.superview == self && button.window && button.enabled && !button.hidden && button.alpha > 0.01 &&
                [button pointInside:[button convertPoint:point fromView:self] withEvent:event]) return button;
        }
    }
    return %orig;
}
%end

%hook UICollectionViewCell
- (void)layoutSubviews {
    %orig;
    NSHashTable *menus = objc_getAssociatedObject(self, "YMDeArrowFeedMenus");
    if (IS_ENABLED(DeArrowEnabled)) for (UIView *menu in menus.allObjects) if (menu.window) YouModUpdateFeedDeArrow(menu);
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
