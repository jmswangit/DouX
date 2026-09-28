#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>

//
//  Hide feed "play interaction" elements:
//   - the anchor link above the creator's username (shop / location / TV show):
//     AWEPlayInteractionAnchorElement exposes shouldShowAnchorView (force NO) and a
//     childView holding the rendered anchor.
//   - the suggested-search / related-search bar at the bottom of a video:
//     TTKFeedSearchRSBannerElement owns the trendingBarView and a
//     hideSearchRSBannerDueToVirtualSignal flag.
//
//  These are components, not plain views, so we drive their own show/hide API (with KVC
//  to their view properties).
//

@interface AWEPlayInteractionAnchorElement : NSObject
@end

@interface TTKFeedSearchRSBannerElement : NSObject
@end

@interface TTKECFeedSearchRSBannerElement : NSObject
@end

static os_log_t feed_elements_log;
static BOOL gBannerProbed;

extern NSMutableString *DouXTabsDebugReport;

static void dx_collapseSearchBanner(id element) {
    if (![DouXManager hideSearchSuggestion]) {
        return;
    }
    id barObject = nil;
    @try {
        barObject = [element valueForKey:@"trendingBarView"];
    } @catch (NSException *exception) {
    }
    if (![barObject isKindOfClass:[UIView class]]) {
        return;
    }
    UIView *bar = (UIView *)barObject;
    bar.hidden = YES;
    bar.alpha = 0.0;

    if (!gBannerProbed) {
        gBannerProbed = YES;
        UIView *v = bar;
        while (v != nil) {
            [DouXTabsDebugReport appendFormat:@"banner-chain: %s frame=%@\n", object_getClassName(v), NSStringFromCGRect(v.frame)];
            v = v.superview;
        }
    }

    BOOL hasZeroHeight = NO;
    for (NSLayoutConstraint *constraint in bar.constraints) {
        BOOL isMine = constraint.firstItem == bar || constraint.secondItem == bar;
        BOOL isHeight = constraint.firstAttribute == NSLayoutAttributeHeight || constraint.secondAttribute == NSLayoutAttributeHeight;
        if (isMine && isHeight && constraint.constant == 0) {
            hasZeroHeight = YES;
            break;
        }
    }
    if (!hasZeroHeight) {
        NSLayoutConstraint *zero = [bar.heightAnchor constraintEqualToConstant:0];
        zero.priority = 999;
        zero.active = YES;
    }
}

static void dx_hideValueView(id object, NSString *key) {
    @try {
        id view = [object valueForKey:key];
        if ([view isKindOfClass:[UIView class]]) {
            ((UIView *)view).hidden = YES;
            ((UIView *)view).alpha = 0.0;
        }
    } @catch (NSException *exception) {
    }
}

static void dx_setBoolValue(id object, NSString *key, BOOL value) {
    @try {
        [object setValue:@(value) forKey:key];
    } @catch (NSException *exception) {
    }
}

%group G_AnchorElement
%hook AWEPlayInteractionAnchorElement
- (BOOL)shouldShowAnchorView {
    if ([DouXManager hideAnchorLink]) {
        return NO;
    }
    return %orig;
}
- (BOOL)shouldShowAnchorViewWithoutCondition {
    if ([DouXManager hideAnchorLink]) {
        return NO;
    }
    return %orig;
}
- (void)componentViewDidLoad {
    %orig;
    if ([DouXManager hideAnchorLink]) {
        dx_hideValueView(self, @"childView");
    }
}
- (void)mountStateDidUpdate {
    %orig;
    if ([DouXManager hideAnchorLink]) {
        dx_hideValueView(self, @"childView");
    }
}
%end
%end

%group G_RSBanner
%hook TTKFeedSearchRSBannerElement
- (void)componentViewDidLoad {
    %orig;
    dx_collapseSearchBanner(self);
}
- (void)containerWillDisplay {
    %orig;
    dx_collapseSearchBanner(self);
}
%end
%end

%group G_RSBannerEC
%hook TTKECFeedSearchRSBannerElement
- (void)mountStateDidUpdate {
    %orig;
    if ([DouXManager hideSearchSuggestion]) {
        dx_setBoolValue(self, @"isShow", NO);
    }
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
}
