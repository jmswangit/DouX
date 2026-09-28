#import "TikTokHeaders.h"
#import "common.h"
#import <os/log.h>

//
//  Inbox tab badge: DMs/System only.
//
//  Probe showed filter-level counts (1 and 13 both == the Activity unread). When enabled
//  we zero the activity filters across all three filter count APIs so the bottom Inbox
//  tab badge no longer reflects likes/comments/follows.
//

@interface TTKNoticeUnreadCountManager : NSObject
@end

static os_log_t inbox_badge_log;

static BOOL dx_isActivityFilter(NSInteger filter) {
    return filter == 1 || filter == 13;
}

%hook TTKNoticeUnreadCountManager

- (NSInteger)unreadCountOfFilter:(NSInteger)filter {
    if ([DouXManager inboxBadgeDmsOnly] && dx_isActivityFilter(filter)) {
        os_log_info(inbox_badge_log, "inboxBadge: zero filter %ld", (long)filter);
        return 0;
    }
    return %orig;
}

- (NSInteger)unreadCountWithShowTypeNumOfFilter:(NSInteger)filter {
    if ([DouXManager inboxBadgeDmsOnly] && dx_isActivityFilter(filter)) {
        return 0;
    }
    return %orig;
}

- (NSInteger)unreadCountOnlyShowTypeRedDotOfFilter:(NSInteger)filter {
    if ([DouXManager inboxBadgeDmsOnly] && dx_isActivityFilter(filter)) {
        return 0;
    }
    return %orig;
}

%end

%ctor {
    inbox_badge_log = os_log_create("com.kunihir0.doux", "InboxBadge");
}
