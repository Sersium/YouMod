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

%hook YTRollingNumberNode

%property (strong, nonatomic) NSString *updatedCount;
%property (strong, nonatomic) NSNumber *updatedCountNumber;

- (id)initWithElement:(id)element context:(id)context {
    self = %orig;
    if (self) {
        self.updatedCount = nil;
        self.updatedCountNumber = nil;
    }
    return self;
}

- (void)updateRollingNumberView {
    %orig;
    if (self.updatedCount && self.updatedCountNumber) {
        [self updateCount:self.updatedCount color:nil];
    }
}

%new(v@:@@)
- (void)updateCount:(NSString *)updatedCount_ color:(UIColor *)color_ {
    @try {
        YTRollingNumberView *view = [self valueForKey:@"_rollingNumberView"];
        if (!view) return;
        UIFont *font = view.font;
        UIColor *color = color_ ?: view.color;
        NSString *updatedCount = [NSString stringWithFormat:@" %@", updatedCount_];
        if ([view respondsToSelector:@selector(setUpdatedCount:updatedCountNumber:font:fontAttributes:color:skipAnimation:)]) {
            [view setUpdatedCount:updatedCount updatedCountNumber:self.updatedCountNumber font:font fontAttributes:view.fontAttributes color:color skipAnimation:YES];
        } else if ([view respondsToSelector:@selector(setUpdatedCount:updatedCountNumber:font:color:skipAnimation:)]) {
            [view setUpdatedCount:updatedCount updatedCountNumber:self.updatedCountNumber font:font color:color skipAnimation:YES];
        }
    } @catch (id ex) {}
}

%end

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

static ELMContainerNode *YouModFindNodeWithIdentifier(ASDisplayNode *root, NSString *targetId) {
    if (!root) return nil;
    if ([root.accessibilityIdentifier isEqualToString:targetId]) {
        return (ELMContainerNode *)root;
    }
    for (ASDisplayNode *child in root.yogaChildren) {
        ELMContainerNode *found = YouModFindNodeWithIdentifier(child, targetId);
        if (found) return found;
    }
    return nil;
}

%hook ASCollectionView

%property (nonatomic, assign) BOOL hasDislikeIntent;

- (ELMCellNode *)nodeForItemAtIndexPath:(NSIndexPath *)indexPath {
    ELMCellNode *node = %orig;
    if (!IS_ENABLED(ReturnYouTubeDislike)) return node;

    // Strictly limit RYD modification to the video action bar!
    // Comments, search, feeds, and channels return immediately without touching Yoga trees.
    if (![self.accessibilityIdentifier isEqualToString:@"id.video.scrollable_action_bar"]) {
        return node;
    }

    ELMContainerNode *likeNode = YouModFindNodeWithIdentifier(node, @"id.video.like.button");
    ELMContainerNode *dislikeNode = YouModFindNodeWithIdentifier(node, @"id.video.dislike.button");

    if (!likeNode) {
        ASDisplayNode *containerNode = node;
        if ([containerNode isKindOfClass:%c(ELMCellNode)]) {
            while (containerNode.yogaChildren.count == 1 || containerNode.yogaChildren.count == 2) {
                if (containerNode.yogaChildren.count == 2) {
                    ASDisplayNode *first = [containerNode.yogaChildren firstObject];
                    if ([first.accessibilityIdentifier isEqualToString:@"id.video.like.button"]) {
                        likeNode = (ELMContainerNode *)first;
                        dislikeNode = (ELMContainerNode *)[containerNode.yogaChildren lastObject];
                        break;
                    }
                    containerNode = containerNode.yogaChildren[1];
                } else {
                    containerNode = [containerNode.yogaChildren firstObject];
                }
            }
        }
    }

    if (likeNode) {
        @try {
            if (!dislikeNode) {
                dislikeNode = YouModFindNodeWithIdentifier(node, @"id.video.dislike.button");
            }
            NSString *videoId = getVideoId(node);
            if (videoId.length == 0) videoId = YouModGetCurrentVideoID();
            if (videoId.length == 0) return node;

            id targetNode = nil;
            if (likeNode.yogaChildren.count >= 2) {
                targetNode = likeNode.yogaChildren[1];
            }
            if (!targetNode) {
                for (ASDisplayNode *child in likeNode.yogaChildren) {
                    if ([child isKindOfClass:%c(YTRollingNumberNode)] || [child isKindOfClass:%c(ELMTextNode)]) {
                        targetNode = child;
                        break;
                    }
                    for (ASDisplayNode *grandchild in child.yogaChildren) {
                        if ([grandchild isKindOfClass:%c(YTRollingNumberNode)] || [grandchild isKindOfClass:%c(ELMTextNode)]) {
                            targetNode = grandchild;
                            break;
                        }
                    }
                    if (targetNode) break;
                }
            }

            __strong YTRollingNumberNode *likeRollingNumberNode = [targetNode isKindOfClass:%c(YTRollingNumberNode)] ? (YTRollingNumberNode *)targetNode : nil;
            __strong ELMTextNode *likeTextNode = [targetNode isKindOfClass:%c(ELMTextNode)] ? (ELMTextNode *)targetNode : nil;

            __strong YTRollingNumberNode *dislikeRollingNumberNode = nil;
            __strong ELMTextNode *dislikeTextNode = nil;

            if (dislikeNode) {
                for (ASDisplayNode *dChild in dislikeNode.yogaChildren) {
                    if ([dChild isKindOfClass:%c(YTRollingNumberNode)]) dislikeRollingNumberNode = (YTRollingNumberNode *)dChild;
                    else if ([dChild isKindOfClass:%c(ELMTextNode)]) dislikeTextNode = (ELMTextNode *)dChild;
                }

                if (!dislikeRollingNumberNode && !dislikeTextNode && targetNode) {
                    if (likeRollingNumberNode) {
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
                    } else if (likeTextNode) {
                        id elementContext = [likeTextNode valueForKey:@"_context"];
                        overrideNodeCreation = 2;
                        dislikeTextNode = [[%c(ELMNodeFactory) sharedInstance] nodeWithElement:likeTextNode.element materializationContext:&elementContext];
                        overrideNodeCreation = 0;
                        NSMutableAttributedString *mDis = [[NSMutableAttributedString alloc] initWithAttributedString:likeTextNode.attributedText];
                        [mDis.mutableString setString:@"..."];
                        dislikeTextNode.attributedText = mDis;
                        [dislikeNode addYogaChild:dislikeTextNode];
                        if (dislikeTextNode.view && dislikeNode.view) {
                            [dislikeNode.view addSubview:dislikeTextNode.view];
                        }
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
                            [mLike.mutableString setString:likeCount];
                            likeTextNode.attributedText = mLike;
                        }
                    }
                    if (IS_ENABLED(RYDShowDislikes)) {
                        if (dislikeRollingNumberNode) {
                            dislikeRollingNumberNode.updatedCount = dislikeCount;
                            dislikeRollingNumberNode.updatedCountNumber = @(dislikes);
                            if ([dislikeRollingNumberNode respondsToSelector:@selector(updateRollingNumberView)]) [dislikeRollingNumberNode updateRollingNumberView];
                            if ([dislikeRollingNumberNode respondsToSelector:@selector(relayoutNode)]) [dislikeRollingNumberNode relayoutNode];
                        } else if (dislikeTextNode) {
                            NSMutableAttributedString *mDis = [[NSMutableAttributedString alloc] initWithAttributedString:dislikeTextNode.attributedText];
                            [mDis.mutableString setString:dislikeCount];
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
            NSInteger dislikes = [votes[@"dislikes"] integerValue];
            NSString *dislikesText = YouModFormatVoteCount(dislikes);

            BOOL updatedExisting = NO;
            for (UIView *sub in view.subviews) {
                if ([sub isKindOfClass:objc_getClass("YTRollingNumberView")]) {
                    updatedExisting = YES;
                    break;
                }
                if ([sub respondsToSelector:@selector(node)]) {
                    id subNode = [sub performSelector:@selector(node)];
                    if ([subNode isKindOfClass:%c(ELMTextNode)] || [subNode isKindOfClass:%c(ASTextNode)]) {
                        NSAttributedString *orig = [subNode attributedText];
                        NSMutableAttributedString *m = orig ? [orig mutableCopy] : [[NSMutableAttributedString alloc] initWithString:dislikesText];
                        [m.mutableString setString:dislikesText];
                        [subNode setAttributedText:m];
                        [sub setNeedsDisplay];
                        updatedExisting = YES;
                        break;
                    }
                }
            }

            if (!updatedExisting) {
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

                CGFloat iconWidth = 24.0;
                CGFloat padding = 4.0;
                lbl.frame = CGRectMake(iconWidth + padding, (view.bounds.size.height - lbl.bounds.size.height) / 2.0, lbl.bounds.size.width, lbl.bounds.size.height);

                CGRect f = view.frame;
                CGFloat reqWidth = iconWidth + padding + lbl.bounds.size.width + 8.0;
                if (f.size.width < reqWidth) {
                    CGFloat diff = reqWidth - f.size.width;
                    f.size.width = reqWidth;
                    view.frame = f;
                    if (view.superview) {
                        CGRect pf = view.superview.frame;
                        pf.size.width += diff;
                        view.superview.frame = pf;
                    }
                }
            }
        } else if ([iden isEqualToString:@"id.video.like.button"] && IS_ENABLED(RYDShowLikes)) {
            NSInteger likes = [votes[@"likes"] integerValue];
            NSString *likesText = YouModFormatVoteCount(likes);
            for (UIView *sub in view.subviews) {
                if ([sub respondsToSelector:@selector(node)]) {
                    id subNode = [sub performSelector:@selector(node)];
                    if ([subNode isKindOfClass:%c(ELMTextNode)] || [subNode isKindOfClass:%c(ASTextNode)]) {
                        NSAttributedString *orig = [subNode attributedText];
                        NSMutableAttributedString *m = orig ? [orig mutableCopy] : [[NSMutableAttributedString alloc] initWithString:likesText];
                        [m.mutableString setString:likesText];
                        [subNode setAttributedText:m];
                        [sub setNeedsDisplay];
                    }
                } else if ([sub isKindOfClass:[UILabel class]] && sub.tag != 0xD1571CE) {
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
