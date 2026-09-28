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

extern NSMutableString *DouXTabsDebugReport;
static BOOL gRSBannerProbed;

static void dx_probeRSBannerContainer(id element) {
    if (gRSBannerProbed || DouXTabsDebugReport == nil) {
        return;
    }
    gRSBannerProbed = YES;
    [DouXTabsDebugReport appendString:@"\n--- RS banner element views ---\n"];

    for (Class cls = object_getClass(element); cls != Nil && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            Ivar ivar = ivars[i];
            const char *typeEncoding = ivar_getTypeEncoding(ivar);
            if (typeEncoding == NULL || typeEncoding[0] != '@') {
                continue;
            }
            id value = nil;
            @try {
                value = object_getIvar(element, ivar);
            } @catch (NSException *exception) {
                continue;
            }
            if ([value isKindOfClass:[UIView class]]) {
                UIView *v = (UIView *)value;
                NSString *heightConstant = @"none";
                for (NSLayoutConstraint *constraint in v.constraints) {
                    if (constraint.firstItem == v && constraint.firstAttribute == NSLayoutAttributeHeight) {
                        heightConstant = [NSString stringWithFormat:@"%.1f", constraint.constant];
                        break;
                    }
                }
                [DouXTabsDebugReport appendFormat:@"%s = %s frame=%@ super=%@ hidden=%d h=%@\n",
                    ivar_getName(ivar), object_getClassName(v), NSStringFromCGRect(v.frame),
                    v.superview ? NSStringFromClass([v.superview class]) : @"(nil)", v.hidden, heightConstant];
            }
        }
        if (ivars != NULL) {
            free(ivars);
        }
    }

    id bar = nil;
    @try {
        bar = [element valueForKey:@"trendingBarView"];
    } @catch (NSException *exception) {
    }
    if ([bar isKindOfClass:[UIView class]]) {
        UIView *v = (UIView *)bar;
        for (int depth = 0; v != nil && depth < 6; depth++) {
            [DouXTabsDebugReport appendFormat:@"trendingBar[%d] = %s frame=%@ super=%@\n",
                depth, object_getClassName(v), NSStringFromCGRect(v.frame),
                v.superview ? NSStringFromClass([v.superview class]) : @"(nil)"];
            v = v.superview;
        }
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
    if ([DouXManager hideSearchSuggestion]) {
        dx_hideValueView(self, @"trendingBarView");
        dx_setBoolValue(self, @"hideSearchRSBannerDueToVirtualSignal", YES);
    }
}
- (void)containerWillDisplay {
    %orig;
    if ([DouXManager hideSearchSuggestion]) {
        dx_hideValueView(self, @"trendingBarView");
        dx_setBoolValue(self, @"hideSearchRSBannerDueToVirtualSignal", YES);
    }
    dx_probeRSBannerContainer(self);
}
- (void)containerDidFullyDisplayWithReason:(id)reason {
    %orig;
    dx_probeRSBannerContainer(self);
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
