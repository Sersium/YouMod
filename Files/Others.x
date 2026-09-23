#import "Headers.h"

// Background playback
%hook MLVideo
- (BOOL)playableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTPlaybackData
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTIPlayerResponse
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTColdConfig
// Try to disable Shorts PiP
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPicture { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPictureIos { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
// Hide startup animations
- (BOOL)mainAppCoreClientIosEnableStartupAnimation { return IS_ENABLED(HideStartupAni) ? NO : %orig; }
// Prevent YouTube from asking "Are you there?"
- (BOOL)enableYouthereCommandsOnIos { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
// Fixes slow miniplayer
- (BOOL)enableIosFloatingMiniplayerDoubleTapToResize { return IS_ENABLED(FixesSlowMiniPlayer) ? NO : %orig; }
// Use old miniplayer
- (BOOL)enableIosFloatingMiniplayer { return IS_ENABLED(DisablesNewMiniPlayer) ? NO : %orig; }
// Fixes the old dialog (the rectangular style) layout incorrectly
- (BOOL)uiSystemsClientGlobalConfigIosEnableActionSheetViewLayoutRefactor { return NO; }
// Remove the new contextual dialog layout styles
- (BOOL)crossPlatformCoreClientGlobalConfigIosEnableBottomSheetPaddingFix { return NO; }
%end

%hook YTHotConfig
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPictureAllowedFromPlayer { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelModel
- (BOOL)isPiPSupported { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelPlayerViewController
- (BOOL)isPictureInPictureAllowed { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
- (void)setupPlayerForPiP { if (!IS_ENABLED(DisablesShortsPiP)) %orig; }
%end

%hook YTReelWatchRootViewController
- (void)switchToPictureInPicture { if (!IS_ENABLED(DisablesShortsPiP)) %orig; }
%end

// Disable Hints
%hook YTSettings
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg {
    if (IS_ENABLED(DisableHints)) arg = YES;
    %orig(arg);
}
%end

%hook YTSettingsImpl
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg {
    if (IS_ENABLED(DisableHints)) arg = YES;
    %orig(arg);
}
%end

%hook YTUserDefaults
- (BOOL)areHintsDisabled { return IS_ENABLED(DisableHints) ? YES : %orig; }
- (void)setHintsDisabled:(BOOL)arg {
    if (IS_ENABLED(DisableHints)) arg = YES;
    %orig(arg);
}
%end

// Block upgrade dialogs
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return IS_ENABLED(BlockUpgradeDialogs) ? YES : %orig; }
- (BOOL)shouldShowUpgradeDialog { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
- (BOOL)shouldShowUpgrade { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
- (BOOL)shouldForceUpgrade { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
%end

%hook YTYouThereController
- (BOOL)shouldShowYouTherePrompt { return IS_ENABLED(HideAreYouThereDialog) ? NO : %orig; }
- (void)showYouTherePrompt { if (!IS_ENABLED(HideAreYouThereDialog)) %orig; }
%end

%hook YTYouThereControllerImpl
- (BOOL)shouldShowYouTherePrompt { return IS_ENABLED(HideAreYouThereDialog) ? NO : %orig; }
- (void)showYouTherePrompt { if (!IS_ENABLED(HideAreYouThereDialog)) %orig; }
%end

// Disables Snackbar
%hook GOOHUDManagerInternal
- (void)showMessageMainThread:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
- (void)activateOverlay:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
- (void)displayHUDViewForMessage:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
%end

// "Play next in queue" (icon 251) and "Add to queue" (icon 895)
%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    int iconnum = renderer.icon.iconType;
    if (iconnum == 251) {
        if (IS_ENABLED(RemovePlayInNextQueueOption)) return NO;
        if (IS_ENABLED(EnablePlayNextInQueue)) return YES;
    } else if (iconnum == 895) {
        if (IS_ENABLED(RemoveAddToLastQueueOption)) return NO;
        if (IS_ENABLED(EnablePlayNextInQueue)) return YES;
    }
    return %orig;
}
%end

%hook YTMenuItemVisibilityHandlerImpl
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    int iconnum = renderer.icon.iconType;
    if (iconnum == 251) {
        if (IS_ENABLED(RemovePlayInNextQueueOption)) return NO;
        if (IS_ENABLED(EnablePlayNextInQueue)) return YES;
    } else if (iconnum == 895) {
        if (IS_ENABLED(RemoveAddToLastQueueOption)) return NO;
        if (IS_ENABLED(EnablePlayNextInQueue)) return YES;
    }
    return %orig;
}
%end

// Remove flyout menu options
%hook YTDefaultSheetController
- (void)addAction:(YTActionSheetAction *)action {
    UIButton *button = action.button;
    NSString *iden = button.accessibilityIdentifier;
    NSString *imageName = [button.currentImage description];

    // Method 1: Filter from accessibilityIdentifier
    NSDictionary *actionsToRemove = @{
        @"7": @(IS_ENABLED(RemoveDownloadOption)),
        @"1": @(IS_ENABLED(RemoveWatchLaterOption)),
        @"3": @(IS_ENABLED(RemoveSaveOption)),
        @"4": @(IS_ENABLED(RemoveRemoveFromPlaylistOption)),
        @"5": @(IS_ENABLED(RemoveShareOption)),
        @"6": @(IS_ENABLED(RemoveShareOption)),
        @"12": @(IS_ENABLED(RemoveNotInterestedOption)),
        @"22": @(IS_ENABLED(RemoveInfoOption)),
        @"36": @(IS_ENABLED(RemoveFilterOption)),
        @"40": @(IS_ENABLED(RemoveNotifyOption)),
        @"58": @(IS_ENABLED(RemoveReportOption))
    };
    if ([actionsToRemove[iden] boolValue]) return;

    // Method 2: Filter from imageName
    NSDictionary *imageNameToRemove = @{
        @"youtube_music": @(IS_ENABLED(RemoveYouTubeMusicOption)),
        @"flag": @(IS_ENABLED(RemoveReportOption)),
        @"alert_bubble": @(IS_ENABLED(RemoveFeedBackOption)),
        @"bookmark": @(IS_ENABLED(RemoveSaveOption)),
        @"circle_slash": @(IS_ENABLED(RemoveNotInterestedOption)),
        @"x_circle": @(IS_ENABLED(RemoveDontRecommendOption)),
        @"chromecast": @(IS_ENABLED(RemoveCastOption)),
        @"shuffle": @(IS_ENABLED(RemoveShuffleOption)),
        @"person_x": @(IS_ENABLED(RemoveUnSubOption)),
        @"help_circle": @(IS_ENABLED(RemoveHelpOption)),
        @"eye_slash": @(IS_ENABLED(RemoveHideFromPlaylistOption)),
        @"player_full_enter_alt": @(IS_ENABLED(RemoveClearScreenOption)),
        @"info_circle": @(IS_ENABLED(RemoveInfoOption))
    };
    for (NSString *key in imageNameToRemove) {
        if ([imageName containsString:key]) {
            if ([imageNameToRemove[key] boolValue]) {
                return;
            }
            break;
        }
    }
    %orig;
}
%end

// YTSlientVote (https://github.com/PoomSmart/YTSilentVote)
%hook YTInnerTubeResponseWrapper
- (id)initWithResponse:(id)response cacheContext:(id)arg2 requestStatistics:(id)arg3 mutableSharedData:(id)arg4 {
    if (IS_ENABLED(HideLikeDislikeVotes)) {
        if ([response isKindOfClass:%c(YTILikeResponse)]
            || [response isKindOfClass:%c(YTIDislikeResponse)]
            || [response isKindOfClass:%c(YTIRemoveLikeResponse)]) return nil;
    }
    return %orig;
}
%end

%hook NSParagraphStyle
+ (NSWritingDirection)defaultWritingDirectionForLanguage:(id)lang { return IS_ENABLED(DisablesRTL) ? NSWritingDirectionLeftToRight : %orig; }
+ (NSWritingDirection)_defaultWritingDirection { return IS_ENABLED(DisablesRTL) ? NSWritingDirectionLeftToRight : %orig; }
%end

%hook UIDevice
- (UIUserInterfaceIdiom)userInterfaceIdiom {
    if (INTFORVAL(DeviceUIIndex) == 1) {
        return UIUserInterfaceIdiomPad;
    } else if (INTFORVAL(DeviceUIIndex) == 2) {
        return UIUserInterfaceIdiomPhone;
    }
    return %orig;
}
%end

%hook UIKeyboardImpl
+ (BOOL)isFloating { return IS_ENABLED(FloatingKeyboard) && isPad() ? YES : %orig; }
%end

%hook YTEngagementPanelHeaderView
- (void)setSubheader:(UIView *)view { if (!IS_ENABLED(HideEngagementSubbar)) %orig; }
- (void)layoutSubviews {
    %orig;
    if (IS_ENABLED(HideInfoButtonPanel)) {
        YTQTMButton *button = self.informationButton;
        if (button != nil) {
            button.hidden = YES;
        }
    }
    for (UIView *button in self.subviews) {
        if ([button isKindOfClass:%c(YTQTMButton)]) {
            YTIButtonRenderer *renderer = [button valueForKey:@"_buttonRenderer"];
            if (renderer == nil) continue;
            NSString *desc = [renderer description];
            if ([desc containsString:@"FEcommunity_page"] && IS_ENABLED(HideCommunityButtonPanel)) {
                button.hidden = YES;
                break;
            }
        }
    }
}
%end

#pragma mark - Clean URLs

static NSString *YouModCleanURLString(NSString *str) {
    if (!str || str.length == 0) return str;
    if (![str containsString:@"youtube.com"] && ![str containsString:@"youtu.be"]) return str;
    
    NSURLComponents *components = [NSURLComponents componentsWithString:str];
    if (!components) return str;
    
    static NSSet *trackingParams = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        trackingParams = [NSSet setWithObjects:
            @"si", @"feature", @"pp", @"fbclid", @"gclid", @"igshid",
            @"ref", @"app", @"context", @"source", @"utm_source",
            @"utm_medium", @"utm_campaign", @"utm_term", @"utm_content", nil
        ];
    });

    NSMutableArray<NSURLQueryItem *> *cleanedItems = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) {
        if (![trackingParams containsObject:item.name.lowercaseString]) {
            [cleanedItems addObject:item];
        }
    }
    components.queryItems = cleanedItems.count > 0 ? cleanedItems : nil;
    return components.URL.absoluteString ?: str;
}

static NSURL *YouModCleanURL(NSURL *url) {
    if (!url) return nil;
    NSString *cleanedStr = YouModCleanURLString(url.absoluteString);
    return [NSURL URLWithString:cleanedStr] ?: url;
}

%hook UIPasteboard
- (void)setString:(NSString *)string {
    if (IS_ENABLED(CleanURLs)) {
        string = YouModCleanURLString(string);
    }
    %orig(string);
}
- (void)setURL:(NSURL *)url {
    if (IS_ENABLED(CleanURLs)) {
        url = YouModCleanURL(url);
    }
    %orig(url);
}
%end

%hook UIActivityViewController
- (instancetype)initWithActivityItems:(NSArray *)activityItems applicationActivities:(NSArray *)applicationActivities {
    if (IS_ENABLED(CleanURLs)) {
        NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:activityItems.count];
        for (id item in activityItems) {
            if ([item isKindOfClass:[NSString class]]) {
                [cleaned addObject:YouModCleanURLString(item)];
            } else if ([item isKindOfClass:[NSURL class]]) {
                [cleaned addObject:YouModCleanURL(item)];
            } else {
                [cleaned addObject:item];
            }
        }
        activityItems = cleaned;
    }
    return %orig(activityItems, applicationActivities);
}
%end

#pragma mark - Comment replies mutation operations as item sections

static YTIItemSectionRenderer *itemSectionRendererWithElements(NSArray *elements) {
    if (elements.count == 0) return nil;
    Class itemSecClass = %c(YTIItemSectionRenderer);
    if (!itemSecClass) return nil;
    YTIItemSectionRenderer *itemSectionRenderer = [[itemSecClass alloc] init];
    NSMutableArray *contentsArray = itemSectionRenderer.contentsArray;
    Class supportedClass = %c(YTIItemSectionSupportedRenderers);
    for (id element in elements) {
        if ([element isKindOfClass:supportedClass]) {
            [contentsArray addObject:element];
            continue;
        }
        if (supportedClass) {
            YTIItemSectionSupportedRenderers *supported = [[supportedClass alloc] init];
            supported.elementRenderer = element;
            [contentsArray addObject:supported];
        }
    }
    return contentsArray.count ? itemSectionRenderer : nil;
}

static void harvestSectionContent(id object, NSMutableArray *itemSectionRenderers, NSMutableArray *elements, NSHashTable *seen, NSInteger depth) {
    if (!object || depth > 8) return;
    if ([seen containsObject:object]) return;
    if ([object isKindOfClass:[NSArray class]]) {
        for (id item in object) harvestSectionContent(item, itemSectionRenderers, elements, seen, depth + 1);
        return;
    }
    if (![object isKindOfClass:%c(GPBMessage)]) return;
    [seen addObject:object];

    if ([object isKindOfClass:%c(YTIItemSectionRenderer)]) {
        [itemSectionRenderers addObject:object];
        return;
    }
    if ([object isKindOfClass:%c(YTIElementRenderer)]) {
        [elements addObject:object];
        return;
    }
    if ([object isKindOfClass:%c(YTIItemSectionSupportedRenderers)]) {
        YTIElementRenderer *elementRenderer = ((YTIItemSectionSupportedRenderers *)object).elementRenderer;
        if (elementRenderer) [elements addObject:elementRenderer];
        return;
    }
    if ([object isKindOfClass:%c(YTISectionListRenderer)]) {
        harvestSectionContent(((YTISectionListRenderer *)object).contentsArray, itemSectionRenderers, elements, seen, depth + 1);
        return;
    }
    if ([object isKindOfClass:%c(YTISectionListMutationOperations)]) {
        if ([object respondsToSelector:@selector(operationsArray)]) {
            harvestSectionContent([(id)object operationsArray], itemSectionRenderers, elements, seen, depth + 1);
        }
        return;
    }
    if ([object isKindOfClass:%c(YTIInsertItemSectionContentOperation)]) {
        if ([object respondsToSelector:@selector(contentsArray)]) {
            harvestSectionContent([(id)object contentsArray], itemSectionRenderers, elements, seen, depth + 1);
        }
        return;
    }
    @try {
        if ([object respondsToSelector:@selector(firstSubmessage)]) {
            harvestSectionContent([(id)object firstSubmessage], itemSectionRenderers, elements, seen, depth + 1);
        }
    } @catch (id ex) {}
}

static NSArray *itemSectionRenderersFromObject(id object) {
    NSMutableArray *itemSectionRenderers = [NSMutableArray array];
    NSMutableArray *elements = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    harvestSectionContent(object, itemSectionRenderers, elements, seen, 0);
    YTIItemSectionRenderer *wrapped = itemSectionRendererWithElements(elements);
    if (wrapped) [itemSectionRenderers insertObject:wrapped atIndex:0];
    return itemSectionRenderers.count ? itemSectionRenderers : nil;
}

static NSArray *normalizedSectionRenderers(NSArray *sectionRenderers) {
    if (sectionRenderers.count == 0) return sectionRenderers;

    NSMutableArray *normalized = [NSMutableArray arrayWithCapacity:sectionRenderers.count];
    BOOL changed = NO;
    for (id renderer in sectionRenderers) {
        if ([renderer isKindOfClass:%c(YTIItemSectionRenderer)]) {
            [normalized addObject:renderer];
            continue;
        }
        BOOL shouldConvert = [renderer isKindOfClass:%c(YTISectionListMutationOperations)]
            || [renderer isKindOfClass:%c(YTIElementRenderer)]
            || [renderer isKindOfClass:%c(YTISectionListSupportedRenderers)];
        NSArray *converted = shouldConvert ? itemSectionRenderersFromObject(renderer) : nil;
        if (converted.count) {
            [normalized addObjectsFromArray:converted];
            changed = YES;
        } else {
            [normalized addObject:renderer];
        }
    }
    return changed ? normalized : sectionRenderers;
}

%hook YTISectionListRenderer
- (NSArray *)sectionRenderers {
    NSArray *sectionRenderers = %orig;
    return normalizedSectionRenderers(sectionRenderers);
}
%end

%hook YTICommentsResponse
- (NSArray *)sectionRenderers {
    NSArray *sectionRenderers = %orig;
    return normalizedSectionRenderers(sectionRenderers);
}
%end

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        CleanURLs: @YES,
        EnablePlayNextInQueue: @YES
    }];
}
