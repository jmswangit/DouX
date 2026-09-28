#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>

//
//  Inbox tab badge separation (probe).
//
//  The Inbox tab badge is driven by TTKNoticeUnreadCountManager, whose counts are
//  per-group (TTKNoticeUnreadCountModel has `group` + `count`). To keep comment-likes off
//  the tab badge while leaving the "Activity & new followers" row badge intact, we first
//  need to know which group comment-likes fall under. This logs each group/type and its
//  count into the debug report (read-only).
//

@interface TTKNoticeUnreadCountManager : NSObject
@end

extern NSMutableString *DouXTabsDebugReport;
static NSMutableSet *gSeenUnreadKeys;

%group G_UnreadProbe
%hook TTKNoticeUnreadCountManager

- (NSInteger)getNoticeUnreadCountWithGroup:(id)group {
    NSInteger count = %orig;
    if (gSeenUnreadKeys == nil) {
        gSeenUnreadKeys = [NSMutableSet set];
    }
    NSString *key = [NSString stringWithFormat:@"g:%@", group];
    if (![gSeenUnreadKeys containsObject:key] && gSeenUnreadKeys.count < 80) {
        [gSeenUnreadKeys addObject:key];
        [DouXTabsDebugReport appendFormat:@"unreadGroup %@ = %ld\n", group, (long)count];
    }
    return count;
}

- (id)getNoticeCountModelWithType:(id)type {
    id model = %orig;
    if (gSeenUnreadKeys == nil) {
        gSeenUnreadKeys = [NSMutableSet set];
    }
    NSString *key = [NSString stringWithFormat:@"t:%@", type];
    if (![gSeenUnreadKeys containsObject:key] && gSeenUnreadKeys.count < 120) {
        [gSeenUnreadKeys addObject:key];
        id count = nil;
        id group = nil;
        @try {
            count = [model valueForKey:@"count"];
            group = [model valueForKey:@"group"];
        } @catch (NSException *exception) {
        }
        [DouXTabsDebugReport appendFormat:@"countModel type=%@ group=%@ count=%@\n", type, group, count];
    }
    return model;
}

- (NSInteger)calculateTotalCountForGroups:(id)groups {
    NSInteger count = %orig;
    if (gSeenUnreadKeys == nil) {
        gSeenUnreadKeys = [NSMutableSet set];
    }
    NSString *key = [NSString stringWithFormat:@"T:%@", groups];
    if (![gSeenUnreadKeys containsObject:key] && gSeenUnreadKeys.count < 160) {
        [gSeenUnreadKeys addObject:key];
        [DouXTabsDebugReport appendFormat:@"totalForGroups %@ = %ld\n", groups, (long)count];
    }
    return count;
}

%end
%end

%ctor {
    if (objc_getClass("TTKNoticeUnreadCountManager") != nil) {
        %init(G_UnreadProbe);
    }
}
