#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

//
//  Hide Tako (TikTok's AI assistant).
//
//  TikTok builds Tako's entrances (feed bottom-right, search, comment bar, ...) out of
//  several view classes. Rather than guessing every internal method, we scan the runtime
//  for every UIView subclass whose class name contains "Tako" (this also catches the
//  Swift classes such as _TtC14TikTokTakoImpl17TakoEntranceButton) and force those views
//  to stay hidden. Two UIView hooks are swizzled: -setHidden: (always YES) and
//  -didMoveToWindow (hide after it joins a window, so it never flashes on screen).
//

static os_log_t hide_tako_log;

static IMP gOrigSetHidden = NULL;
static IMP gOrigDidMoveToWindow = NULL;

static void dx_setHidden(id self, SEL _cmd, BOOL hidden) {
    ((void (*)(id, SEL, BOOL))gOrigSetHidden)(self, _cmd, YES);
}

static void dx_didMoveToWindow(id self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigDidMoveToWindow)(self, _cmd);
    ((void (*)(id, SEL, BOOL))gOrigSetHidden)(self, @selector(setHidden:), YES);
}

static BOOL dx_isUIView(Class cls) {
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
        const char *name = class_getName(cls);
        if (name == NULL || strstr(name, "Tako") == NULL) {
            continue;
        }
        if (!dx_isUIView(cls)) {
            continue;
        }
        dx_hideClass(cls);
    }

    free(classes);
}

%ctor {
    if (![DouXManager hideTako]) {
        return;
    }

    hide_tako_log = os_log_create("com.kunihir0.doux", "HideTako");

    gOrigSetHidden = class_getMethodImplementation([UIView class], @selector(setHidden:));
    gOrigDidMoveToWindow = class_getMethodImplementation([UIView class], @selector(didMoveToWindow));

    dx_scanTakoViews();

    os_log_info(hide_tako_log, "hideTako: applied");
}
