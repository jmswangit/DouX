#import "TikTokHeaders.h"
#import "common.h"
#import <os/log.h>

//
//  Inbox tab badge: DMs/System only.
//
//  Filters weren't the source, so the Inbox tab badge comes from unreadData: (keys 3/10
//  were 1 in the probe). We zero the activity keys here.
//

@interface TTKNoticeUnreadCountManager : NSObject
@end

static os_log_t inbox_badge_log;

static BOOL dx_isActivityKey(unsigned long long key) {
    return key == 3 || key == 10;
}

%hook TTKNoticeUnreadCountManager

- (id)unreadData:(unsigned long long)key {
    if ([DouXManager inboxBadgeDmsOnly] && dx_isActivityKey(key)) {
        os_log_info(inbox_badge_log, "inboxBadge: zero unreadData %llu", key);
        return @0;
    }
    return %orig;
}

- (id)unreadData:(unsigned long long)key context:(id)context {
    if ([DouXManager inboxBadgeDmsOnly] && dx_isActivityKey(key)) {
        return @0;
    }
    return %orig;
}

%end

%ctor {
    inbox_badge_log = os_log_create("com.kunihir0.doux", "InboxBadge");
}
