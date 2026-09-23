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

@interface YTRollingNumberView (RYD)
@property (nonatomic, strong) UIColor *color;
@end

@interface YTRollingNumberNode (RYD)
@property (nonatomic, copy) NSString *updatedCount;
@property (nonatomic, copy) NSNumber *updatedCountNumber;
- (id)element;
- (void)updateRollingNumberView;
- (void)updateCount:(NSString *)count color:(UIColor *)color;
- (void)relayoutNode;
@end

@interface ELMNodeFactory (RYD)
+ (instancetype)sharedInstance;
- (id)nodeWithElement:(id)element materializationContext:(const void *)context;
@end

@interface ASDisplayNode (YouModRYDYoga)
- (void)addYogaChild:(id)child;
- (NSArray *)yogaChildren;
- (id)closestViewController;
@end

@interface ASCollectionView (RYD)
@property (nonatomic, assign) BOOL hasDislikeIntent;
@property (nonatomic, assign) BOOL isProbablyVideoDescriptionHeaderPanel;
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

static NSString *getVideoId(ASDisplayNode *containerNode) {
    NSString *current = YouModGetCurrentVideoID();
    if (current && current.length > 0) return current;

    UIViewController *vc = [containerNode closestViewController];
    if (![vc isKindOfClass:%c(YTWatchNextResultsViewController)]) {
        UIViewController *parentViewController;
        do {
            parentViewController = vc.parentViewController;
            if ([parentViewController isKindOfClass:%c(YTWatchViewController)]) {
                vc = parentViewController;
                break;
            }
            vc = parentViewController;
        } while (parentViewController);
        if ([parentViewController isKindOfClass:%c(YTWatchViewController)]) {
            @try {
                NSString *vid = [parentViewController valueForKeyPath:@"_videoID"];
                if (vid.length > 0) return vid;
            } @catch (id ex) {}
        }
    }
    YTPlayerViewController *pvc;
    NSObject *wc;
    @try {
        wc = [vc valueForKey:@"_metadataPanelStateProvider"];
    } @catch (id ex) {
        @try { wc = [vc valueForKey:@"_ngwMetadataPanelStateProvider"]; } @catch (id ex2) {}
    }
    @try {
        YTWatchPlaybackController *wpc = ((YTWatchController *)wc).watchPlaybackController;
        pvc = [wpc valueForKey:@"_playerViewController"];
    } @catch (id ex) {
        @try { pvc = [wc valueForKey:@"_playerViewController"]; } @catch (id ex2) {}
    }
    @try {
        NSString *vid = [pvc contentVideoID];
        if (vid.length > 0) return vid;
    } @catch (id ex) {}
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

%hook YTSingleVideoController
- (void)setPlayerResponse:(YTIPlayerResponse *)response {
    %orig;
    if (response.videoDetails.videoId.length > 0) {
        currentActiveVideoID = [response.videoDetails.videoId copy];
        if (IS_ENABLED(ReturnYouTubeDislike)) {
            [[YouModRYDManager sharedInstance] fetchVotesForVideoID:currentActiveVideoID completion:nil];
        }
    }
}
%end

#pragma mark - Node Factory & CollectionView Hooks

static int overrideNodeCreation = 0;

%hook ELMNodeFactory

- (Class)classForElement:(id)element materializationContext:(const void *)context {
    switch (overrideNodeCreation) {
        case 1:
            return %c(YTRollingNumberNode);
        case 2:
            return %c(ELMTextNode);
        default:
            return %orig;
    }
}

%end

static NSString *getElementDescription(ELMCellNode *node) {
    if (![node isKindOfClass:%c(ELMCellNode)]) return nil;
    @try {
        ELMNodeController *controller = [node controller];
        return [[controller owningComponent] description];
    } @catch (id ex) {
        return nil;
    }
}

static BOOL isVideoScrollableActionBar(ASCollectionView *collectionView, ELMCellNode *node) {
    return [collectionView.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"];
}

static BOOL isVideoDescriptionHeader(ASCollectionView *collectionView, ELMCellNode *node) {
    return [getElementDescription(node) containsString:@"video_description_header.eml"];
}

%hook ASCollectionView

%property (nonatomic, assign) BOOL hasDislikeIntent;
%property (nonatomic, assign) BOOL isProbablyVideoDescriptionHeaderPanel;

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        @try {
            self.isProbablyVideoDescriptionHeaderPanel = [[self _viewControllerForAncestor].navigationController isKindOfClass:%c(YTEngagementPanelNavigationController)];
        } @catch (id ex) {}
    }
}

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    ELMCellNode *node = %orig;
    if (!IS_ENABLED(ReturnYouTubeDislike)) return node;

    // Video details description header panel
    if (self.isProbablyVideoDescriptionHeaderPanel && isVideoDescriptionHeader(self, node)) {
        NSString *videoId = getVideoId(node);
        if (videoId.length == 0) return node;

        @try {
            ELMContainerNode *rootContainerNode = [node.yogaChildren firstObject];
            ELMContainerNode *mainContainerNode = rootContainerNode.yogaChildren[1];
            ELMContainerNode *likeContainerNode = [mainContainerNode.yogaChildren firstObject];
            ELMContainerNode *rollingNumberContainerNode = [likeContainerNode.yogaChildren firstObject];

            if (rollingNumberContainerNode.yogaChildren.count == 1) {
                YTRollingNumberNode *infoLikeRollingNumberNode = [rollingNumberContainerNode.yogaChildren firstObject];
                id elementContext = [infoLikeRollingNumberNode valueForKey:@"_context"];
                overrideNodeCreation = 1;
                YTRollingNumberNode *infoDislikeRollingNumberNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:infoLikeRollingNumberNode.element materializationContext:&elementContext];
                overrideNodeCreation = 0;
                infoDislikeRollingNumberNode.updatedCount = @"...";
                infoDislikeRollingNumberNode.updatedCountNumber = @(0);
                if ([infoDislikeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) {
                    [infoDislikeRollingNumberNode updateRollingNumberView];
                }
                [rollingNumberContainerNode addYogaChild:infoDislikeRollingNumberNode];
                if (infoDislikeRollingNumberNode.view && rollingNumberContainerNode.view) {
                    [rollingNumberContainerNode.view addSubview:infoDislikeRollingNumberNode.view];
                }

                self.hasDislikeIntent = YES;
                [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoId completion:^(NSDictionary *votes) {
                    if (!votes) return;
                    NSInteger dislikes = [votes[@"dislikes"] integerValue];
                    NSString *dislikeCount = YouModFormatVoteCount(dislikes);
                    NSInteger likes = [votes[@"likes"] integerValue];
                    NSString *likeCount = YouModFormatVoteCount(likes);

                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (IS_ENABLED(RYDShowLikes)) {
                            infoLikeRollingNumberNode.updatedCount = likeCount;
                            infoLikeRollingNumberNode.updatedCountNumber = @(likes);
                            if ([infoLikeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) {
                                [infoLikeRollingNumberNode updateRollingNumberView];
                            }
                            if ([infoLikeRollingNumberNode respondsToSelector:@selector(relayoutNode)]) {
                                [infoLikeRollingNumberNode relayoutNode];
                            }
                        }
                        infoDislikeRollingNumberNode.updatedCount = [NSString stringWithFormat:@"• %@", dislikeCount];
                        infoDislikeRollingNumberNode.updatedCountNumber = @(dislikes);
                        if ([infoDislikeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) {
                            [infoDislikeRollingNumberNode updateRollingNumberView];
                        }
                        if ([infoDislikeRollingNumberNode respondsToSelector:@selector(relayoutNode)]) {
                            [infoDislikeRollingNumberNode relayoutNode];
                        }
                    });
                }];
            }

            if (likeContainerNode.yogaChildren.count > 1) {
                ELMTextNode *infoLikeTextNode = likeContainerNode.yogaChildren[1];
                if (![infoLikeTextNode.attributedText.string containsString:@"•"]) {
                    NSMutableAttributedString *likeText = [[NSMutableAttributedString alloc] initWithAttributedString:infoLikeTextNode.attributedText];
                    likeText.mutableString.string = [likeText.string stringByAppendingString:@" • Dislike"];
                    infoLikeTextNode.attributedText = likeText;
                }
            }
        } @catch (id ex) {}
    }
    // Main video scrollable action bar (thumbs up and thumbs down)
    else if (isVideoScrollableActionBar(self, node)) {
        @try {
            int pairMode = -1;
            BOOL isDislikeButtonModified = NO;
            ASDisplayNode *containerNode = node;
            ELMContainerNode *likeNode = nil;

            if (![containerNode isKindOfClass:%c(ELMCellNode)]) return node;

            do {
                containerNode = [containerNode.yogaChildren firstObject];
                if (containerNode.yogaChildren.count == 2)
                    containerNode = containerNode.yogaChildren[1];
            } while (containerNode.yogaChildren.count == 1);

            likeNode = [containerNode.yogaChildren firstObject];
            if (![likeNode.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) return node;

            NSString *videoId = getVideoId(node);
            if (videoId.length == 0) return node;

            ELMContainerNode *dislikeNode = [containerNode.yogaChildren lastObject];
            isDislikeButtonModified = dislikeNode.yogaChildren.count == 2;

            __strong YTRollingNumberNode *likeRollingNumberNode = nil;
            __strong YTRollingNumberNode *dislikeRollingNumberNode = nil;
            __strong ELMTextNode *likeTextNode = nil;
            __strong ELMTextNode *dislikeTextNode = nil;

            if (likeNode.yogaChildren.count == 2) {
                id targetNode = likeNode.yogaChildren[1];
                if ([targetNode isKindOfClass:%c(YTRollingNumberNode)]) {
                    likeRollingNumberNode = (YTRollingNumberNode *)targetNode;
                    if (isDislikeButtonModified) {
                        dislikeRollingNumberNode = dislikeNode.yogaChildren[1];
                    } else {
                        id elementContext = [likeRollingNumberNode valueForKey:@"_context"];
                        overrideNodeCreation = 1;
                        dislikeRollingNumberNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:likeRollingNumberNode.element materializationContext:&elementContext];
                        overrideNodeCreation = 0;
                        dislikeRollingNumberNode.updatedCount = @"...";
                        dislikeRollingNumberNode.updatedCountNumber = @(0);
                        if ([dislikeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) {
                            [dislikeRollingNumberNode updateRollingNumberView];
                        }
                        [dislikeNode addYogaChild:dislikeRollingNumberNode];
                        if (dislikeRollingNumberNode.view && dislikeNode.view) {
                            [dislikeNode.view addSubview:dislikeRollingNumberNode.view];
                        }
                        pairMode = 0;
                    }
                } else if ([targetNode isKindOfClass:%c(ELMTextNode)]) {
                    likeTextNode = (ELMTextNode *)targetNode;
                    if (isDislikeButtonModified) {
                        dislikeTextNode = dislikeNode.yogaChildren[1];
                    } else {
                        id elementContext = [likeTextNode valueForKey:@"_context"];
                        overrideNodeCreation = 2;
                        dislikeTextNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:likeTextNode.element materializationContext:&elementContext];
                        overrideNodeCreation = 0;
                        NSMutableAttributedString *mDisText = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                        mDisText.mutableString.string = @"...";
                        dislikeTextNode.attributedText = mDisText;
                        [dislikeNode addYogaChild:dislikeTextNode];
                        if (dislikeTextNode.view && dislikeNode.view) {
                            [dislikeNode.view addSubview:dislikeTextNode.view];
                        }
                        pairMode = 0;
                    }
                }
            }

            self.hasDislikeIntent = YES;
            [[YouModRYDManager sharedInstance] fetchVotesForVideoID:videoId completion:^(NSDictionary *votes) {
                if (!votes) return;
                NSInteger dislikes = [votes[@"dislikes"] integerValue];
                NSString *dislikeCount = YouModFormatVoteCount(dislikes);
                NSInteger likes = [votes[@"likes"] integerValue];
                NSString *likeCount = YouModFormatVoteCount(likes);

                dispatch_async(dispatch_get_main_queue(), ^{
                    if (IS_ENABLED(RYDShowLikes)) {
                        if (likeRollingNumberNode) {
                            likeRollingNumberNode.updatedCount = likeCount;
                            likeRollingNumberNode.updatedCountNumber = @(likes);
                            if ([likeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) [likeRollingNumberNode updateRollingNumberView];
                            if ([likeRollingNumberNode respondsToSelector:@selector(relayoutNode)]) [likeRollingNumberNode relayoutNode];
                        } else if (likeTextNode) {
                            NSMutableAttributedString *mLike = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                            mLike.mutableString.string = likeCount;
                            likeTextNode.attributedText = mLike;
                        }
                    }
                    if (IS_ENABLED(RYDShowDislikes)) {
                        NSString *dislikeString = (pairMode == 0) ? [NSString stringWithFormat:@"  %@ ", dislikeCount] : dislikeCount;
                        if (dislikeRollingNumberNode) {
                            dislikeRollingNumberNode.updatedCount = dislikeString;
                            dislikeRollingNumberNode.updatedCountNumber = @(dislikes);
                            if ([dislikeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) [dislikeRollingNumberNode updateRollingNumberView];
                            if ([dislikeRollingNumberNode respondsToSelector:@selector(relayoutNode)]) [dislikeRollingNumberNode relayoutNode];
                        } else if (dislikeTextNode) {
                            NSMutableAttributedString *mDis = [[NSMutableAttributedString alloc] initWithAttributedString:dislikeTextNode.attributedText];
                            mDis.mutableString.string = dislikeString;
                            dislikeTextNode.attributedText = mDis;
                        }
                    }
                });
            }];
        } @catch (id ex) {}
    }

    return node;
}

%end

#pragma mark - _ASDisplayView & Button Fallbacks

// Helpers to apply votes
static void YouModApplyRYDVotes(_ASDisplayView *view, NSDictionary *votes, NSString *iden) {
    if (!view || !votes) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        view.clipsToBounds = NO;
        if (view.superview) view.superview.clipsToBounds = NO;

        if ([iden isEqualToString:@"id.video.dislike.button"]) {
            // If already handled by Texture yoga child, don't overlap with a UILabel
            for (UIView *sub in view.subviews) {
                if ([sub isKindOfClass:objc_getClass("YTRollingNumberView")] ||
                    [sub isKindOfClass:objc_getClass("ASTextNodeView")] ||
                    [sub isKindOfClass:objc_getClass("ELMTextNodeView")]) {
                    return;
                }
            }

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

// Update main player action bar buttons (_ASDisplayView)
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

    self.clipsToBounds = NO;
    if (self.superview) self.superview.clipsToBounds = NO;

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
        self.clipsToBounds = NO;
        if (self.superview) self.superview.clipsToBounds = NO;
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
        RYDShowDislikes: @YES,
        @"RYD-ENABLED": @YES,
        @"RYD-USE-LIKE-DATA": @YES,
        @"RYD-EXACT-NUMBER": @NO
    }];
}
