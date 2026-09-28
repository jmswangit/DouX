#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>

//
//  Hide feed "play interaction" elements:
//   - the anchor link above the creator's username (shop / location / TV show)
//   - the suggested-search (related search) banner at the bottom of a video
//
//  Both are AWEPlayInteraction / TTKFeed*Element views; we hide the element view itself
//  when it joins a window. The isKindOfClass guard keeps it safe if a given element isn't
//  actually a UIView.
//

@interface AWEPlayInteractionAnchorElement : UIView
@end

@interface TTKFeedSearchRSBannerElement : UIView
@end

@interface TTKECFeedSearchRSBannerElement : UIView
@end

@interface TTKPlayPhotoAlbumFullPageSuggestedSearchElement : UIView
@end

static os_log_t feed_elements_log;

static void dx_applyHidden(UIView *view, BOOL shouldHide) {
    if (view == nil || ![view isKindOfClass:[UIView class]]) {
        return;
    }
    if (shouldHide) {
        view.hidden = YES;
        view.alpha = 0.0;
    }
}

static void dx_hideAnchorElement(UIView *view) {
    if ([DouXManager hideAnchorLink]) {
        dx_applyHidden(view, YES);
    }
}

static void dx_hideSearchElement(UIView *view) {
    if ([DouXManager hideSearchSuggestion]) {
        dx_applyHidden(view, YES);
    }
}

%group G_AnchorElement
%hook AWEPlayInteractionAnchorElement
- (void)didMoveToWindow {
    %orig;
    dx_hideAnchorElement(self);
}
- (void)layoutSubviews {
    %orig;
    dx_hideAnchorElement(self);
}
%end
%end

%group G_RSBanner
%hook TTKFeedSearchRSBannerElement
- (void)didMoveToWindow {
    %orig;
    dx_hideSearchElement(self);
}
- (void)layoutSubviews {
    %orig;
    dx_hideSearchElement(self);
}
%end
%end

%group G_RSBannerEC
%hook TTKECFeedSearchRSBannerElement
- (void)didMoveToWindow {
    %orig;
    dx_hideSearchElement(self);
}
- (void)layoutSubviews {
    %orig;
    dx_hideSearchElement(self);
}
%end
%end

%group G_PhotoAlbumSuggestedSearch
%hook TTKPlayPhotoAlbumFullPageSuggestedSearchElement
- (void)didMoveToWindow {
    %orig;
    dx_hideSearchElement(self);
}
- (void)layoutSubviews {
    %orig;
    dx_hideSearchElement(self);
}
%end
%end

%ctor {
    feed_elements_log = os_log_create("com.kunihir0.doux", "FeedElements");

    if (objc_getClass("AWEPlayInteractionAnchorElement") != nil) {
        %init(G_AnchorElement);
    }
    if (objc_getClass("TTKFeedSearchRSBannerElement") != nil) {
        %init(G_RSBanner);
    }
    if (objc_getClass("TTKECFeedSearchRSBannerElement") != nil) {
        %init(G_RSBannerEC);
    }
    if (objc_getClass("TTKPlayPhotoAlbumFullPageSuggestedSearchElement") != nil) {
        %init(G_PhotoAlbumSuggestedSearch);
    }
}
