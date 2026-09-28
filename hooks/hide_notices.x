#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>
#import <string.h>

@interface NSObject (DouXNoticeFlags)
- (BOOL)isFromDiggCommentNotification;
@end

//
//  Hide "liked your comment" entries from the Activity / inbox list.
//
//  Notice items are rendered from section view models whose model arrays are set through
//  -setModelsArray: (and a few notice-specific list setters). We filter those arrays and
//  drop any item that reports -isFromDiggCommentNotification == YES (the exact flag
//  TikTok sets on "someone liked your comment" notices), with a class-name fallback for
//  older/newer model shapes.
//
//  NOTE: the section view-model class names below are best-effort. If a build uses a
//  different class, the guard simply skips it. Enable the toggle, open the Activity tab,
//  and check the log line "saw notice model ..." to confirm which models flow through.
//

static os_log_t hide_notices_log;
static NSMutableSet *dx_seenNoticeClasses;

static BOOL dx_shouldDrop(id model) {
    if (model == nil) {
        return NO;
    }

    if ([model respondsToSelector:@selector(isFromDiggCommentNotification)]) {
        if ([model isFromDiggCommentNotification]) {
            return YES;
        }
    }

    const char *name = object_getClassName(model);
    if (name != NULL && strstr(name, "Digg") != NULL && strstr(name, "Comment") != NULL) {
        return YES;
    }
    return NO;
}

static NSArray *dx_filterNotices(NSArray *models) {
    if (![DouXManager hideCommentLikeNotices]) {
        return models;
    }
    if (![models isKindOfClass:[NSArray class]] || models.count == 0) {
        return models;
    }

    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:models.count];
    for (id model in models) {
        const char *name = object_getClassName(model);

        if (name != NULL && (strstr(name, "Notice") != NULL || strstr(name, "Notification") != NULL)) {
            NSString *className = [NSString stringWithUTF8String:name];
            if (className != nil && ![dx_seenNoticeClasses containsObject:className]) {
                [dx_seenNoticeClasses addObject:className];
                os_log_info(hide_notices_log, "hideCommentLikes: saw notice model %{public}s", name);
            }
        }

        if (dx_shouldDrop(model)) {
            os_log_info(hide_notices_log, "hideCommentLikes: dropped %{public}s", name);
        } else {
            [kept addObject:model];
        }
    }
    return kept;
}

%group DXBaseSection
%hook AWEBaseListSectionViewModel
- (void)setModelsArray:(NSArray *)modelsArray {
    %orig(dx_filterNotices(modelsArray));
}
%end
%end

%group DXNoticeSectionBase
%hook TTKNoticeBaseSectionViewModel
- (void)setModelsArray:(NSArray *)modelsArray {
    %orig(dx_filterNotices(modelsArray));
}
%end
%end

%group DXNoticeListBase
%hook TTKNoticeListBaseSectionViewModel
- (void)setModelsArray:(NSArray *)modelsArray {
    %orig(dx_filterNotices(modelsArray));
}
%end
%end

%group DXClassifiedDataController
%hook TTKClassifiedNoticeListDataController
- (void)setNoticeList:(NSArray *)noticeList {
    %orig(dx_filterNotices(noticeList));
}
- (void)setNoticeItemList:(NSArray *)noticeItemList {
    %orig(dx_filterNotices(noticeItemList));
}
%end
%end

%group DXNoticeSubListVM
%hook TTKNoticeSubListViewModel
- (void)setModelsArray:(NSArray *)modelsArray {
    %orig(dx_filterNotices(modelsArray));
}
%end
%end

%group DXClassifiedTabVM
%hook TTKClassifiedNoticeTabViewModel
- (void)setModelsArray:(NSArray *)modelsArray {
    %orig(dx_filterNotices(modelsArray));
}
%end
%end

%ctor {
    if (![DouXManager hideCommentLikeNotices]) {
        return;
    }

    hide_notices_log = os_log_create("com.kunihir0.doux", "HideCommentLikes");
    dx_seenNoticeClasses = [NSMutableSet set];

    if ([objc_getClass("AWEBaseListSectionViewModel") instancesRespondToSelector:@selector(setModelsArray:)]) {
        %init(DXBaseSection);
    }
    if ([objc_getClass("TTKNoticeBaseSectionViewModel") instancesRespondToSelector:@selector(setModelsArray:)]) {
        %init(DXNoticeSectionBase);
    }
    if ([objc_getClass("TTKNoticeListBaseSectionViewModel") instancesRespondToSelector:@selector(setModelsArray:)]) {
        %init(DXNoticeListBase);
    }
    if ([objc_getClass("TTKClassifiedNoticeListDataController") instancesRespondToSelector:@selector(setNoticeList:)]) {
        %init(DXClassifiedDataController);
    }
    if ([objc_getClass("TTKNoticeSubListViewModel") instancesRespondToSelector:@selector(setModelsArray:)]) {
        %init(DXNoticeSubListVM);
    }
    if ([objc_getClass("TTKClassifiedNoticeTabViewModel") instancesRespondToSelector:@selector(setModelsArray:)]) {
        %init(DXClassifiedTabVM);
    }

    os_log_info(hide_notices_log, "hideCommentLikes: applied");
}
