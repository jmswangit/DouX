#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

//
//  Top feed tabs and bottom tab bar toggles.
//
//  Top tabs are configured from model arrays (feedTabModels / tabBarItems) whose items
//  expose an id (feedTabID) and/or a title. Bottom bar items are TTKTabBar*Item models
//  (TTKTabBarMallItem = Shop, TTKTabBarShootItem = the + button); the + button itself is
//  the AWETabBarPlusButton view. We filter the model arrays and hide the + view.
//

@interface AWETabBarPlusButton : UIButton
@end

static os_log_t tabs_log;

static NSString *dx_stringForKeys(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        @try {
            id value = [object valueForKey:key];
            if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
                return value;
            }
            if ([value isKindOfClass:[NSNumber class]]) {
                return [value stringValue];
            }
        } @catch (NSException *exception) {
            // ignore unknown keys
        }
    }
    return nil;
}

static BOOL dx_shouldHideTopTab(id item) {
    NSString *identifier = dx_stringForKeys(item, @[@"feedTabID", @"tabID", @"tabId", @"identifier", @"itemType", @"pageName", @"tabType"]);
    NSString *title = dx_stringForKeys(item, @[@"title", @"tabTitle", @"tabName", @"name", @"text"]);
    NSString *ident = identifier.lowercaseString ?: @"";
    NSString *name = title.lowercaseString ?: @"";

    if ([DouXManager hideTabForYou] &&
        ([ident isEqualToString:@"homepage_hot"] || [ident isEqualToString:@"homepage_foryou"] || [ident containsString:@"foryou"] || [name containsString:@"for you"])) {
        return YES;
    }
    if ([DouXManager hideTabFollowing] &&
        ([ident isEqualToString:@"homepage_follow"] || [ident isEqualToString:@"homepage_following"] || [name containsString:@"following"])) {
        return YES;
    }
    if ([DouXManager hideTabFriends] &&
        ([ident isEqualToString:@"homepage_friends"] || [name containsString:@"friends"])) {
        return YES;
    }
    if ([DouXManager hideTabLocal] &&
        ([ident isEqualToString:@"homepage_nearby"] || [ident isEqualToString:@"homepage_local"] || [name isEqualToString:@"local"] || [name isEqualToString:@"nearby"])) {
        return YES;
    }
    if ([DouXManager hideTabCommunity] &&
        ([ident isEqualToString:@"homepage_community"] || [name containsString:@"community"])) {
        return YES;
    }
    return NO;
}

static BOOL dx_shouldHideBottomTab(id item) {
    const char *className = object_getClassName(item);
    if (className == NULL) {
        return NO;
    }
    NSString *cls = [NSString stringWithUTF8String:className];

    if ([DouXManager hideTabShop] && ([cls containsString:@"Mall"] || [cls containsString:@"Shop"])) {
        return YES;
    }
    if ([DouXManager hideTabPlus] && ([cls containsString:@"Shoot"] || [cls containsString:@"Plus"] || [cls containsString:@"Upload"] || [cls containsString:@"Create"])) {
        return YES;
    }
    return NO;
}

static NSArray *dx_filterTabList(NSArray *items) {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
        return items;
    }

    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if (dx_shouldHideTopTab(item) || dx_shouldHideBottomTab(item)) {
            os_log_info(tabs_log, "tabs: dropped %{public}s", object_getClassName(item));
        } else {
            [kept addObject:item];
        }
    }
    return kept;
}

%group G_TikTokFeedTabControl
%hook TikTokFeedTabControl
- (void)setFeedTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
- (void)setTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
- (void)setTabItems:(NSArray *)items { %orig(dx_filterTabList(items)); }
- (void)setTabBarItems:(NSArray *)items { %orig(dx_filterTabList(items)); }
%end
%end

%group G_TTKFeedTabBarControlConfig
%hook TTKFeedTabBarControlConfig
- (void)setFeedTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
- (void)setTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
- (void)setTabItems:(NSArray *)items { %orig(dx_filterTabList(items)); }
- (void)setTabBarItems:(NSArray *)items { %orig(dx_filterTabList(items)); }
%end
%end

%group G_TTKFeedTabConfig
%hook TTKFeedTabConfig
- (void)setFeedTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
- (void)setTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
%end
%end

%group G_TTKTabBarManager
%hook TTKTabBarManager
- (void)setTabBarItems:(NSArray *)items { %orig(dx_filterTabList(items)); }
- (void)setTabItems:(NSArray *)items { %orig(dx_filterTabList(items)); }
- (void)setTabModels:(NSArray *)models { %orig(dx_filterTabList(models)); }
%end
%end

%hook AWETabBarPlusButton
- (void)didMoveToWindow {
    %orig;
    if ([DouXManager hideTabPlus]) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}
- (void)layoutSubviews {
    %orig;
    if ([DouXManager hideTabPlus]) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
}
%end

%ctor {
    tabs_log = os_log_create("com.kunihir0.doux", "Tabs");

    if (objc_getClass("TikTokFeedTabControl") != nil) {
        %init(G_TikTokFeedTabControl);
    }
    if (objc_getClass("TTKFeedTabBarControlConfig") != nil) {
        %init(G_TTKFeedTabBarControlConfig);
    }
    if (objc_getClass("TTKFeedTabConfig") != nil) {
        %init(G_TTKFeedTabConfig);
    }
    if (objc_getClass("TTKTabBarManager") != nil) {
        %init(G_TTKTabBarManager);
    }
}
