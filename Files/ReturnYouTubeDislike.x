#import "Headers.h"

// Return YouTube Dislike (RYD) Integration for YouMod
// API: https://returnyoutubedislikeapi.com/votes?videoId={videoId}

static NSString * const kYMReturnDislikeNotification = @"YouModReturnDislikeNotification";
static NSString *currentActiveVideoID = nil;

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
        if ([_inFlightRequests containsObject:videoID]) {
            if (completion) completion(nil);
            return;
        }
        [_inFlightRequests addObject:videoID];
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
        [self.votesCache setObject:voteData forKey:videoID];

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:kYMReturnDislikeNotification object:nil userInfo:@{@"videoID": videoID, @"votes": voteData}];
            if (completion) completion(voteData);
        });
    }];
    [task resume];
}

@end

#pragma mark - Hooks

static NSString *YouModGetCurrentVideoID(void) {
    if (currentActiveVideoID && currentActiveVideoID.length > 0) return currentActiveVideoID;
    if (YouModCurrentPlayerViewController) {
        @try {
            YTIPlayerResponse *resp = [YouModCurrentPlayerViewController valueForKey:@"playerResponse"];
            NSString *vid = resp.videoDetails.videoId;
            if (vid.length > 0) return vid;
        } @catch (id e) {}
    }
    return nil;
}

// Capture current video ID from player
%hook YTPlayerViewController
- (void)setPlayerResponse:(YTIPlayerResponse *)response {
    %orig;
    if (response.videoDetails.videoId.length > 0) {
        currentActiveVideoID = [response.videoDetails.videoId copy];
        if (IS_ENABLED(ReturnYouTubeDislike)) {
            [[YouModRYDManager sharedInstance] fetchVotesForVideoID:currentActiveVideoID completion:nil];
        }
    }
}

- (void)loadVideoWithPlaybackData:(id)data {
    %orig;
    NSString *vID = nil;
    @try {
        vID = [data valueForKey:@"videoId"];
    } @catch (id ex) {}
    if (vID.length > 0) {
        currentActiveVideoID = [vID copy];
        if (IS_ENABLED(ReturnYouTubeDislike)) {
            [[YouModRYDManager sharedInstance] fetchVotesForVideoID:currentActiveVideoID completion:nil];
        }
    }
}
%end

// Helpers to apply votes
static void YouModApplyRYDVotes(_ASDisplayView *view, NSDictionary *votes, NSString *iden) {
    if (!view || !votes) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([iden isEqualToString:@"id.video.dislike.button"]) {
            NSInteger dislikes = [votes[@"dislikes"] integerValue];
            NSString *dislikesText = YouModFormatVoteCount(dislikes);

            UILabel *lbl = [view viewWithTag:0xD1571CE];
            if (!lbl) {
                lbl = [[UILabel alloc] init];
                lbl.tag = 0xD1571CE;
                lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
                lbl.textColor = [UIColor whiteColor];
                lbl.textAlignment = NSTextAlignmentLeft;
                [view addSubview:lbl];
            }
            lbl.text = dislikesText;
            [lbl sizeToFit];

            // Position label next to the thumbs down icon
            CGFloat iconWidth = 24.0;
            CGFloat padding = 4.0;
            lbl.frame = CGRectMake(iconWidth + padding, (view.bounds.size.height - lbl.bounds.size.height) / 2.0, lbl.bounds.size.width, lbl.bounds.size.height);
        } else if ([iden isEqualToString:@"id.video.like.button"] && IS_ENABLED(RYDShowLikes)) {
            NSInteger likes = [votes[@"likes"] integerValue];
            NSString *likesText = YouModFormatVoteCount(likes);
            for (UIView *sub in view.subviews) {
                if ([sub isKindOfClass:[UILabel class]] && sub.tag != 0xD1571CE) {
                    UILabel *likeLbl = (UILabel *)sub;
                    if (likeLbl.text.length > 0 && ![likeLbl.text isEqualToString:likesText]) {
                        likeLbl.text = likesText;
                    }
                }
            }
        }
    });
}

static void YouModApplyRYDVotesToButton(YTQTMButton *btn, NSDictionary *votes, NSString *iden) {
    if (!btn || !votes) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([iden isEqualToString:@"id.video.dislike.button"]) {
            NSInteger dislikes = [votes[@"dislikes"] integerValue];
            NSString *dislikesText = YouModFormatVoteCount(dislikes);
            [btn setTitle:dislikesText forState:UIControlStateNormal];
            [btn setTitle:dislikesText forState:UIControlStateSelected];
        } else if ([iden isEqualToString:@"id.video.like.button"] && IS_ENABLED(RYDShowLikes)) {
            NSInteger likes = [votes[@"likes"] integerValue];
            NSString *likesText = YouModFormatVoteCount(likes);
            [btn setTitle:likesText forState:UIControlStateNormal];
            [btn setTitle:likesText forState:UIControlStateSelected];
        }
    });
}

// Update main player action bar buttons (ASDisplayView)
%hook _ASDisplayView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:kYMReturnDislikeNotification object:nil];
        return;
    }
    if (!IS_ENABLED(ReturnYouTubeDislike)) return;

    NSString *iden = self.accessibilityIdentifier;
    if (![iden isEqualToString:@"id.video.dislike.button"] && ![iden isEqualToString:@"id.video.like.button"]) return;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(youmod_onDislikeNotification:) name:kYMReturnDislikeNotification object:nil];

    NSString *videoID = YouModGetCurrentVideoID();
    if (!videoID) return;

    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoID];
    if (votes) {
        YouModApplyRYDVotes(self, votes, iden);
    } else {
        [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoID completion:^(NSDictionary *fetchedVotes) {
            if (fetchedVotes) {
                YouModApplyRYDVotes(self, fetchedVotes, iden);
            }
        }];
    }
}

- (void)layoutSubviews {
    %orig;
    if (!IS_ENABLED(ReturnYouTubeDislike)) return;
    UILabel *lbl = [self viewWithTag:0xD1571CE];
    if (lbl) {
        CGFloat iconWidth = 24.0;
        CGFloat padding = 4.0;
        lbl.frame = CGRectMake(iconWidth + padding, (self.bounds.size.height - lbl.bounds.size.height) / 2.0, lbl.bounds.size.width, lbl.bounds.size.height);
    }
}

%new
- (void)youmod_onDislikeNotification:(NSNotification *)note {
    NSString *videoID = note.userInfo[@"videoID"];
    if (!videoID || ![videoID isEqualToString:YouModGetCurrentVideoID()]) return;
    NSDictionary *votes = note.userInfo[@"votes"];
    YouModApplyRYDVotes(self, votes, self.accessibilityIdentifier);
}

%end

// Fallback for button controls using YTQTMButton
%hook YTQTMButton

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;
    if (!IS_ENABLED(ReturnYouTubeDislike)) return;

    NSString *iden = self.accessibilityIdentifier;
    if (![iden isEqualToString:@"id.video.dislike.button"] && ![iden isEqualToString:@"id.video.like.button"]) return;

    NSString *videoID = YouModGetCurrentVideoID();
    if (!videoID) return;

    NSDictionary *votes = [[YouModRYDManager sharedInstance] cachedVotesForVideoID:videoID];
    if (votes) {
        YouModApplyRYDVotesToButton(self, votes, iden);
    } else {
        [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoID completion:^(NSDictionary *fetchedVotes) {
            if (fetchedVotes) {
                YouModApplyRYDVotesToButton(self, fetchedVotes, iden);
            }
        }];
    }
}

%end

// YouTube Shorts like/dislike counts
%hook YTReelWatchLikesController

- (void)updateLikeButtonWithRenderer:(id)renderer {
    %orig;
    if (!IS_ENABLED(ReturnYouTubeDislike)) return;

    NSString *vID = nil;
    @try {
        vID = [renderer valueForKeyPath:@"target.videoId"];
    } @catch (id ex) {}

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
        RYDShowDislikes: @YES
    }];
}
