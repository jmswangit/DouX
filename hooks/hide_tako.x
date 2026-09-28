#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

//
//  Hide Tako (TikTok's AI assistant).
//
//  TikTok's internal name for Tako is "TikBot" (e.g. AWEFeedTikBotButton), so matching
//  only "Tako" misses the feed entrance. We scan the runtime for every UIView subclass
//  whose class name contains any known Tako/AI-assistant fragment and force those views
//  invisible (hidden + alpha 0).
//

static os_log_t hide_tako_log;

static IMP gOrigSetHidden = NULL;
static IMP gOrigSetAlpha = NULL;
static IMP gOrigDidMoveToWindow = NULL;

static const char *kTakoNameFragments[] = {
    "Tako",
    "TikBot",
    "AiBot",
    "AIBot",
    "AskAI",
    "AskTako",
    "AiEntrance",
    "AIEntrance",
    "AiAssistant",
    "AIAssistant",
};

static void dx_setHidden(id self, SEL _cmd, BOOL hidden) {
    ((void (*)(id, SEL, BOOL))gOrigSetHidden)(self, _cmd, YES);
}

static void dx_setAlpha(id self, SEL _cmd, CGFloat alpha) {
    ((void (*)(id, SEL, CGFloat))gOrigSetAlpha)(self, _cmd, 0.0);
}

static void dx_didMoveToWindow(id self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigDidMoveToWindow)(self, _cmd);
    ((void (*)(id, SEL, BOOL))gOrigSetHidden)(self, @selector(setHidden:), YES);
    ((void (*)(id, SEL, CGFloat))gOrigSetAlpha)(self, @selector(setAlpha:), 0.0);
}

static BOOL dx_isTakoView(Class cls) {
    const char *name = class_getName(cls);
    if (name == NULL) {
        return NO;
    }

    BOOL matched = NO;
    size_t count = sizeof(kTakoNameFragments) / sizeof(kTakoNameFragments[0]);
    for (size_t i = 0; i < count; i++) {
        if (strstr(name, kTakoNameFragments[i]) != NULL) {
            matched = YES;
            break;
        }
    }
    if (!matched) {
        return NO;
    }

    for (Class c = cls; c != Nil; c = class_getSuperclass(c)) {
        if (c == [UIView class]) {
            return YES;
        }
    }
    return NO;
}

static void dx_hideClass(Class cls) {
    if (cls == Nil) {
        return;
    }

    Method setHiddenMethod = class_getInstanceMethod(cls, @selector(setHidden:));
    if (setHiddenMethod != NULL) {
        if (!class_addMethod(cls, @selector(setHidden:), (IMP)dx_setHidden, method_getTypeEncoding(setHiddenMethod))) {
            method_setImplementation(class_getInstanceMethod(cls, @selector(setHidden:)), (IMP)dx_setHidden);
        }
    }

    Method setAlphaMethod = class_getInstanceMethod(cls, @selector(setAlpha:));
    if (setAlphaMethod != NULL) {
        if (!class_addMethod(cls, @selector(setAlpha:), (IMP)dx_setAlpha, method_getTypeEncoding(setAlphaMethod))) {
            method_setImplementation(class_getInstanceMethod(cls, @selector(setAlpha:)), (IMP)dx_setAlpha);
        }
    }

    Method didMoveMethod = class_getInstanceMethod(cls, @selector(didMoveToWindow));
    if (didMoveMethod != NULL) {
        if (!class_addMethod(cls, @selector(didMoveToWindow), (IMP)dx_didMoveToWindow, method_getTypeEncoding(didMoveMethod))) {
            method_setImplementation(class_getInstanceMethod(cls, @selector(didMoveToWindow)), (IMP)dx_didMoveToWindow);
        }
    }

    os_log_info(hide_tako_log, "hideTako: hiding view class %{public}s", class_getName(cls));
}

static void dx_scanTakoViews(void) {
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
        if (dx_isTakoView(cls)) {
            dx_hideClass(cls);
        }
    }

    free(classes);
}

%ctor {
    if (![DouXManager hideTako]) {
        return;
    }

    hide_tako_log = os_log_create("com.kunihir0.doux", "HideTako");

    gOrigSetHidden = class_getMethodImplementation([UIView class], @selector(setHidden:));
    gOrigSetAlpha = class_getMethodImplementation([UIView class], @selector(setAlpha:));
    gOrigDidMoveToWindow = class_getMethodImplementation([UIView class], @selector(didMoveToWindow));

    dx_scanTakoViews();

    os_log_info(hide_tako_log, "hideTako: applied");
}
