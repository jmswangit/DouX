#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

//
//  Top feed tabs and bottom tab bar toggles.
//
//  Rather than guessing which class owns the tab list (they differ per build), we swizzle
//  every class that implements a known tab-list getter/setter at load, and filter the
//  returned/incoming array. Top tabs are matched by feedTabID / title; bottom items by
//  their TTKTabBar*Item class name (TTKTabBarMallItem = Shop, TTKTabBarShootItem = +).
//

@interface AWETabBarPlusButton : UIButton
@end

static os_log_t tabs_log;
static NSMutableDictionary *gOrigIMPs;
static NSMutableString *gReport;

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

static IMP dx_origIMP(Class cls, SEL sel) {
    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(c), sel_getName(sel)];
        NSValue *value = gOrigIMPs[key];
        if (value != nil) {
            return [value pointerValue];
        }
    }
    return NULL;
}

static void dx_setterReplacement(id self, SEL _cmd, id argument) {
    IMP orig = dx_origIMP(object_getClass(self), _cmd);
    if (orig == NULL) {
        return;
    }
    (void)((void (*)(id, SEL, id))orig)(self, _cmd, dx_filterTabList(argument));
}

static id dx_getterReplacement(id self, SEL _cmd) {
    IMP orig = dx_origIMP(object_getClass(self), _cmd);
    if (orig == NULL) {
        return nil;
    }
    id result = ((id (*)(id, SEL))orig)(self, _cmd);
    if ([result isKindOfClass:[NSArray class]]) {
        return dx_filterTabList(result);
    }
    return result;
}

static id dx_transformReplacement(id self, SEL _cmd, id argument) {
    IMP orig = dx_origIMP(object_getClass(self), _cmd);
    if (orig == NULL) {
        return nil;
    }
    return ((id (*)(id, SEL, id))orig)(self, _cmd, dx_filterTabList(argument));
}

static BOOL dx_anyTabToggleEnabled(void) {
    return [DouXManager hideTabCommunity] || [DouXManager hideTabLocal] || [DouXManager hideTabFollowing] ||
           [DouXManager hideTabFriends] || [DouXManager hideTabForYou] || [DouXManager hideTabShop] || [DouXManager hideTabPlus];
}

static void dx_swizzleSelectorEverywhere(SEL sel) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) {
        return;
    }
    Class *classes = (Class *)malloc(sizeof(Class) * (size_t)count);
    if (classes == NULL) {
        return;
    }
    objc_getClassList(classes, count);

    for (int i = 0; i < count; i++) {
        Class cls = classes[i];

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        BOOL implements = NO;
        for (unsigned int j = 0; j < methodCount; j++) {
            if (method_getName(methods[j]) == sel) {
                implements = YES;
                break;
            }
        }
        if (methods != NULL) {
            free(methods);
        }
        if (!implements) {
            continue;
        }

        Method method = class_getInstanceMethod(cls, sel);
        if (method == NULL) {
            continue;
        }

        char *returnType = method_copyReturnType(method);
        unsigned int argumentCount = method_getNumberOfArguments(method);
        IMP replacement = NULL;

        if (argumentCount == 3) {
            if (returnType != NULL && returnType[0] == 'v') {
                replacement = (IMP)dx_setterReplacement;
            } else if (returnType != NULL && returnType[0] == '@') {
                replacement = (IMP)dx_transformReplacement;
            }
        } else if (argumentCount == 2) {
            if (returnType != NULL && returnType[0] == '@') {
                replacement = (IMP)dx_getterReplacement;
            }
        }
        if (returnType != NULL) {
            free(returnType);
        }
        if (replacement == NULL) {
            continue;
        }

        IMP original = method_getImplementation(method);
        NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(cls), sel_getName(sel)];
        gOrigIMPs[key] = [NSValue valueWithPointer:original];
        method_setImplementation(method, replacement);

        os_log_info(tabs_log, "tabs: swizzled %s on %s", sel_getName(sel), class_getName(cls));
        [gReport appendFormat:@"%s -> %s\n", sel_getName(sel), class_getName(cls)];
    }

    free(classes);
}

%group G_PlusButton
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
%end

%ctor {
    tabs_log = os_log_create("com.kunihir0.doux", "Tabs");
    gOrigIMPs = [NSMutableDictionary dictionary];
    gReport = [NSMutableString string];

    if (objc_getClass("AWETabBarPlusButton") != nil) {
        %init(G_PlusButton);
    }

    [gReport appendFormat:@"toggles community=%d local=%d following=%d friends=%d foryou=%d shop=%d plus=%d\n",
        [DouXManager hideTabCommunity], [DouXManager hideTabLocal], [DouXManager hideTabFollowing],
        [DouXManager hideTabFriends], [DouXManager hideTabForYou], [DouXManager hideTabShop], [DouXManager hideTabPlus]];

    if (!dx_anyTabToggleEnabled()) {
        [gReport appendString:@"no top/tab-bar toggle enabled\n"];
    } else {
        static const char *selectors[] = {
            "setFeedTabModels:",
            "setTabModels:",
            "setTabBarItems:",
            "setTabItems:",
            "setTabInfos:",
            "setTabConfigs:",
            "setTabBarConfigs:",
            "setTabList:",
            "setTabsArray:",
            "setTabConfigsArray:",
            "setTabInfosArray:",
            "setTabItemsArrayForTabList:",
            "setTabListArray:",
            "configTabbarViewWithTabModels:",
            "feedTabModels",
            "tabModels",
            "tabBarItems",
            "tabItems",
            "tabInfos",
            "tabConfigs",
            "tabBarConfigs",
            "tabList",
            "tabsArray",
            "tabListArray",
            "tabItemsArrayForTabList",
        };

        size_t selectorCount = sizeof(selectors) / sizeof(selectors[0]);
        for (size_t i = 0; i < selectorCount; i++) {
            dx_swizzleSelectorEverywhere(sel_registerName(selectors[i]));
        }
    }

    [[NSUserDefaults standardUserDefaults] setObject:gReport forKey:@"tab_debug_report"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
