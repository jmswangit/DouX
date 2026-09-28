#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

//
//  Top feed tabs (TTKFeedTopTabItemInfo) and bottom tab bar (TikTokTabBarImpl.
//  TTKTabBarItemsManager) toggles.
//
//  We swizzle every class that implements a known tab-list getter/setter and filter the
//  array. Matching uses both an id (KVC) and a title/name. A debug report records which
//  selectors/classes were hooked and which item classes were seen.
//

@interface AWETabBarPlusButton : UIButton
@end

@interface AWETabBarButton : UIView
@end

@interface TTKTabBarButton : UIView
@end

static os_log_t tabs_log;
static NSMutableDictionary *gOrigIMPs;
NSMutableString *DouXTabsDebugReport;
static NSInteger gDropLogCount;
static NSMutableSet *gSeenItemClasses;

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
        }
    }
    return nil;
}

static NSString *dx_itemIdentifier(id item) {
    return dx_stringForKeys(item, @[@"feedTabID", @"tabID", @"tabId", @"identifier", @"barItemID", @"barItemId", @"tabKey", @"itemType", @"tabType", @"pageName", @"key", @"type"]);
}

static NSString *dx_itemTitle(id item) {
    return dx_stringForKeys(item, @[@"title", @"tabTitle", @"tabName", @"name", @"displayName", @"text"]);
}

static BOOL dx_match(NSString *value, NSArray<NSString *> *tokens) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
        return NO;
    }
    NSString *lower = value.lowercaseString;
    for (NSString *token in tokens) {
        NSString *t = token.lowercaseString;
        if ([lower isEqualToString:t] || [lower containsString:t]) {
            return YES;
        }
    }
    return NO;
}

static BOOL dx_shouldHideTopTab(id item) {
    NSString *ident = dx_itemIdentifier(item);
    NSString *title = dx_itemTitle(item);

    if ([DouXManager hideTabForYou] &&
        (dx_match(ident, @[@"homepage_hot", @"for_you", @"foryou", @"for you"]) || dx_match(title, @[@"for you"]))) {
        return YES;
    }
    if ([DouXManager hideTabFollowing] &&
        (dx_match(ident, @[@"homepage_follow", @"following", @"follow"]) || dx_match(title, @[@"following"]))) {
        return YES;
    }
    if ([DouXManager hideTabFriends] &&
        (dx_match(ident, @[@"homepage_friends", @"friends", @"friend"]) || dx_match(title, @[@"friends"]))) {
        return YES;
    }
    if ([DouXManager hideTabLocal] &&
        (dx_match(ident, @[@"homepage_nearby", @"homepage_local", @"nearby", @"local"]) || dx_match(title, @[@"local", @"nearby"]))) {
        return YES;
    }
    if ([DouXManager hideTabCommunity] &&
        (dx_match(ident, @[@"homepage_explore", @"homepage_community", @"community"]) || dx_match(title, @[@"community"]))) {
        return YES;
    }
    return NO;
}

static BOOL dx_shouldHideBottomTab(id item) {
    if ([item isKindOfClass:[NSNumber class]]) {
        NSInteger value = [item integerValue];
        if ([DouXManager hideTabShop] && value == 7) {
            return YES;
        }
        if ([DouXManager hideTabPlus] && value == 2) {
            return YES;
        }
        return NO;
    }
    NSString *ident = dx_itemIdentifier(item);
    NSString *title = dx_itemTitle(item);
    const char *className = object_getClassName(item);
    NSString *cls = className != NULL ? [NSString stringWithUTF8String:className] : @"";

    if ([DouXManager hideTabShop] &&
        (dx_match(cls, @[@"Mall", @"Shop"]) || dx_match(ident, @[@"mall", @"shop"]) || dx_match(title, @[@"shop", @"mall"]))) {
        return YES;
    }
    if ([DouXManager hideTabPlus] &&
        (dx_match(cls, @[@"Shoot", @"Plus", @"Upload", @"Create"]) || dx_match(ident, @[@"shoot", @"plus", @"upload", @"create"]) || dx_match(title, @[@"upload", @"create"]))) {
        return YES;
    }
    return NO;
}

static BOOL dx_shouldHideSidebarItem(id item) {
    if (![DouXManager hideSidebarArrow]) {
        return NO;
    }
    if ([item isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)item lowercaseString];
        return [lower containsString:@"sidebar"];
    }
    const char *className = object_getClassName(item);
    if (className != NULL) {
        NSString *cls = [NSString stringWithUTF8String:className].lowercaseString;
        if ([cls containsString:@"sidebar"]) {
            return YES;
        }
    }
    return dx_match(dx_itemIdentifier(item), @[@"sidebar", @"side_bar"]) || dx_match(dx_itemTitle(item), @[@"sidebar"]);
}

static NSArray *dx_filterTabList(NSArray *items, const char *selectorName) {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
        return items;
    }

    NSMutableArray *kept = nil;
    for (NSUInteger index = 0; index < items.count; index++) {
        id item = items[index];
        const char *itemClassName = object_getClassName(item);
        {
            NSString *itemIdent = dx_itemIdentifier(item);
            NSString *seen = [NSString stringWithFormat:@"%s|%@|%s", selectorName, itemIdent ?: @"", itemClassName ?: ""];
            if (![gSeenItemClasses containsObject:seen] && gSeenItemClasses.count < 300) {
                [gSeenItemClasses addObject:seen];
                [DouXTabsDebugReport appendFormat:@"  item@%s = %s id=%@\n", selectorName, itemClassName, itemIdent];
            }
        }

        if (dx_shouldHideTopTab(item) || dx_shouldHideBottomTab(item) || dx_shouldHideSidebarItem(item)) {
            os_log_info(tabs_log, "tabs: dropped %{public}s", itemClassName);
            if (gDropLogCount < 40) {
                gDropLogCount++;
                [DouXTabsDebugReport appendFormat:@"  DROPPED@%s = %s (id=%@)\n", selectorName, itemClassName, dx_itemIdentifier(item)];
            }
            if (kept == nil) {
                kept = [NSMutableArray arrayWithArray:[items subarrayWithRange:NSMakeRange(0, index)]];
            }
        } else if (kept != nil) {
            [kept addObject:item];
        }
    }
    return kept != nil ? kept : items;
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
    (void)((void (*)(id, SEL, id))orig)(self, _cmd, dx_filterTabList(argument, sel_getName(_cmd)));
}

static id dx_getterReplacement(id self, SEL _cmd) {
    IMP orig = dx_origIMP(object_getClass(self), _cmd);
    if (orig == NULL) {
        return nil;
    }
    id result = ((id (*)(id, SEL))orig)(self, _cmd);
    if ([result isKindOfClass:[NSArray class]]) {
        return dx_filterTabList(result, sel_getName(_cmd));
    }
    if ([result isKindOfClass:[NSDictionary class]] && [DouXManager hideSidebarArrow]) {
        NSDictionary *dict = result;
        NSMutableDictionary *filtered = [NSMutableDictionary dictionaryWithCapacity:dict.count];
        BOOL dropped = NO;
        for (id key in dict) {
            if ([key isKindOfClass:[NSString class]]) {
                NSString *keyLower = [(NSString *)key lowercaseString];
                if ([keyLower containsString:@"sidebar"]) {
                    dropped = YES;
                    [DouXTabsDebugReport appendFormat:@"  DROPPED_DICT_KEY@%s = %@\n", sel_getName(_cmd), key];
                    continue;
                }
            }
            filtered[key] = dict[key];
        }
        return dropped ? filtered : result;
    }
    return result;
}

static id dx_transformReplacement(id self, SEL _cmd, id argument) {
    IMP orig = dx_origIMP(object_getClass(self), _cmd);
    if (orig == NULL) {
        return nil;
    }
    return ((id (*)(id, SEL, id))orig)(self, _cmd, dx_filterTabList(argument, sel_getName(_cmd)));
}

// For "add one item" methods (appendWithTabBarItem: / addBarItem:). If the item should be
// hidden we swallow the call entirely, so the bar never creates its button and the
// remaining items reflow.
static void dx_addItemReplacement(id self, SEL _cmd, id argument) {
    IMP orig = dx_origIMP(object_getClass(self), _cmd);
    if (orig == NULL) {
        return;
    }
    if ([argument isKindOfClass:[NSArray class]]) {
        (void)((void (*)(id, SEL, id))orig)(self, _cmd, dx_filterTabList(argument, sel_getName(_cmd)));
        return;
    }
    if (dx_shouldHideTopTab(argument) || dx_shouldHideBottomTab(argument) || dx_shouldHideSidebarItem(argument)) {
        [DouXTabsDebugReport appendFormat:@"  SKIP_ADD@%s = %s id=%@\n", sel_getName(_cmd), object_getClassName(argument), dx_itemIdentifier(argument)];
        return;
    }
    (void)((void (*)(id, SEL, id))orig)(self, _cmd, argument);
}

static BOOL dx_anyTabToggleEnabled(void) {
    return [DouXManager hideTabCommunity] || [DouXManager hideTabLocal] || [DouXManager hideTabFollowing] ||
           [DouXManager hideTabFriends] || [DouXManager hideTabForYou] || [DouXManager hideTabShop] || [DouXManager hideTabPlus] ||
           [DouXManager hideSidebarArrow];
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
        if (strcmp(class_getName(cls), "DouX") == 0) {
            continue;
        }

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
        [DouXTabsDebugReport appendFormat:@"swizzled %s -> %s\n", sel_getName(sel), class_getName(cls)];
    }

    free(classes);
}

static void dx_swizzleAddSelectorEverywhere(SEL sel) {
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
        if (strcmp(class_getName(cls), "DouX") == 0) {
            continue;
        }

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
        if (method == NULL || method_getNumberOfArguments(method) != 3) {
            continue;
        }

        IMP original = method_getImplementation(method);
        NSString *key = [NSString stringWithFormat:@"%s|%s", class_getName(cls), sel_getName(sel)];
        gOrigIMPs[key] = [NSValue valueWithPointer:original];
        method_setImplementation(method, (IMP)dx_addItemReplacement);
        [DouXTabsDebugReport appendFormat:@"swizzled %s -> %s\n", sel_getName(sel), class_getName(cls)];
    }

    free(classes);
}

static void dx_dumpMethods(const char *className) {
    Class cls = objc_getClass(className);
    if (cls == Nil) {
        [DouXTabsDebugReport appendFormat:@"\n(no class %s)\n", className];
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    [DouXTabsDebugReport appendFormat:@"\n--- methods of %s ---\n", className];
    for (unsigned int i = 0; i < count; i++) {
        [DouXTabsDebugReport appendFormat:@"%s\n", sel_getName(method_getName(methods[i]))];
    }
    if (methods != NULL) {
        free(methods);
    }
}

static NSString *dx_firstTextInView(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) {
        return ((UILabel *)view).text;
    }
    for (UIView *sub in view.subviews) {
        NSString *text = dx_firstTextInView(sub);
        if (text.length > 0) {
            return text;
        }
    }
    return nil;
}

static BOOL gBarProbed;

static void dx_probeTabBar(UIView *bar) {
    if (bar == nil) {
        return;
    }
    if (!gBarProbed) {
        gBarProbed = YES;
        [DouXTabsDebugReport appendString:@"\n--- bottom bar subviews ---\n"];
        for (UIView *sub in bar.subviews) {
            [DouXTabsDebugReport appendFormat:@"%s text=%@\n", object_getClassName(sub), dx_firstTextInView(sub)];
        }
    }
    if ([DouXManager hideTabShop]) {
        for (UIView *sub in bar.subviews) {
            NSString *text = dx_firstTextInView(sub);
            if (text.length > 0 && [[text lowercaseString] containsString:@"shop"]) {
                sub.hidden = YES;
                sub.alpha = 0.0;
                os_log_info(tabs_log, "tabs: hid shop button %{public}s", object_getClassName(sub));
            }
        }
    }
}

static void dx_hideTabBarButtonIfShop(UIView *button) {
    if (![DouXManager hideTabShop]) {
        return;
    }
    NSString *text = dx_firstTextInView(button);
    if (text.length > 0 && [[text lowercaseString] containsString:@"shop"]) {
        button.hidden = YES;
        button.alpha = 0.0;
    }
}

%group G_PlusButton
%hook AWETabBarPlusButton
- (void)didMoveToWindow {
    %orig;
    if ([DouXManager hideTabPlus]) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
    dx_probeTabBar(self.superview);
}
- (void)layoutSubviews {
    %orig;
    if ([DouXManager hideTabPlus]) {
        self.hidden = YES;
        self.alpha = 0.0;
    }
    dx_probeTabBar(self.superview);
}
%end
%end

%group G_TabBarButton
%hook TTKTabBarButton
- (void)didMoveToWindow {
    %orig;
    dx_hideTabBarButtonIfShop(self);
}
- (void)layoutSubviews {
    %orig;
    dx_hideTabBarButtonIfShop(self);
}
%end
%end

%ctor {
    tabs_log = os_log_create("com.kunihir0.doux", "Tabs");
    gOrigIMPs = [NSMutableDictionary dictionary];
    DouXTabsDebugReport = [NSMutableString string];
    gSeenItemClasses = [NSMutableSet set];

    if (objc_getClass("AWETabBarPlusButton") != nil) {
        %init(G_PlusButton);
    }
    if (objc_getClass("TTKTabBarButton") != nil) {
        %init(G_TabBarButton);
    }

    [DouXTabsDebugReport appendFormat:@"toggles community=%d local=%d following=%d friends=%d foryou=%d shop=%d plus=%d sidebar=%d\n",
        [DouXManager hideTabCommunity], [DouXManager hideTabLocal], [DouXManager hideTabFollowing],
        [DouXManager hideTabFriends], [DouXManager hideTabForYou], [DouXManager hideTabShop], [DouXManager hideTabPlus], [DouXManager hideSidebarArrow]];

    static const char *selectors[] = {
        // top feed tabs (TTKTabTopEntranceResult)
        "topTabs",
        "setTopTabs:",
        // bottom tab bar (TTKTabBar*Item)
        "tabBarItems",
        "setTabBarItems:",
        "visibleTabBarItems",
        "decisionItemList",
        "itemSelectModels",
        // feed tab-bar corner items (sidebar arrow)
        "tabCornerItems",
        "placeholderCornerItemTypes",
        "cornerItems",
    };

    size_t selectorCount = sizeof(selectors) / sizeof(selectors[0]);
    if (dx_anyTabToggleEnabled()) {
        for (size_t i = 0; i < selectorCount; i++) {
            dx_swizzleSelectorEverywhere(sel_registerName(selectors[i]));
        }

        static const char *addSelectors[] = {
            "appendWithTabBarItem:",
            "addBarItem:",
        };
        size_t addSelectorCount = sizeof(addSelectors) / sizeof(addSelectors[0]);
        for (size_t i = 0; i < addSelectorCount; i++) {
            dx_swizzleAddSelectorEverywhere(sel_registerName(addSelectors[i]));
        }
    } else {
        [DouXTabsDebugReport appendString:@"no top/tab-bar toggle enabled\n"];
    }

    dx_dumpMethods("TUXSwift.TUXTabBar");
    dx_dumpMethods("AWESlidingTabbarView");
    dx_dumpMethods("TikTokTabBarImpl.TTKTabBarItemsManager");
    dx_dumpMethods("TTKTabBarManager");

    [[NSUserDefaults standardUserDefaults] setObject:DouXTabsDebugReport forKey:@"tab_debug_report"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}
