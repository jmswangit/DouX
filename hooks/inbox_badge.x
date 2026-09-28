#import "TikTokHeaders.h"
#import "common.h"
#import <os/log.h>

//
//  Inbox tab badge: DMs/System only.
//
//  Probe showed the badge counts are filter-level (filter 1 == the aggregate that
//  includes Activity). When enabled, we drop filter 1's contribution so the bottom Inbox
//  tab badge no longer reflects likes/comments/follows — only real notifications.
//  The "Activity & new followers" row badge comes from the notice list, not this filter,
//  so it is left intact.
//

@interface TTKNoticeUnreadCountManager : NSObject
@end

static os_log_t inbox_badge_log;

%hook TTKNoticeUnreadCountManager
- (NSInteger)unreadCountOfFilter:(NSInteger)filter {
    if ([DouXManager inboxBadgeDmsOnly] && filter == 1) {
        os_log_info(inbox_badge_log, "inboxBadge: zeroing activity filter 1 for tab badge");
        return 0;
    }
    return %orig;
}
%end

%ctor {
    inbox_badge_log = os_log_create("com.kunihir0.doux", "InboxBadge");
}
