#import "TikTokHeaders.h"
#import "common.h"
#import <objc/runtime.h>
#import <os/log.h>

//
//  Inbox tab badge separation (probe, correct scalar signatures).
//
//  TTKNoticeUnreadCountManager:
//    - getNoticeUnreadCountWithGroup:(NSInteger) -> NSInteger
//    - getNoticeCountModelWithType:(NSInteger)  -> TTKNoticeUnreadCountModel (id)
//    - calculateTotalCountForGroups:(NSArray *)  -> NSInteger
//  Groups/types are integers. We log each group/type and its count so we can identify the
//  comment-like group and subtract it from the total that feeds the Inbox tab badge only.
//

@interface TTKNoticeUnreadCountManager : NSObject
@end

extern NSMutableString *DouXTabsDebugReport;
static NSMutableSet *gSeenKeys;

static void dx_logOnce(NSString *key, NSString *line) {
    if (gSeenKeys == nil) {
        gSeenKeys = [NSMutableSet set];
    }
    if ([gSeenKeys containsObject:key] || gSeenKeys.count >= 120) {
        return;
    }
    [gSeenKeys addObject:key];
    [DouXTabsDebugReport appendFormat:@"%@\n", line];
}

%group G_UnreadProbe
%hook TTKNoticeUnreadCountManager

- (NSInteger)getNoticeUnreadCountWithGroup:(NSInteger)group {
    NSInteger count = %orig;
    dx_logOnce([NSString stringWithFormat:@"g:%ld", (long)group],
               [NSString stringWithFormat:@"unreadGroup %ld = %ld", (long)group, (long)count]);
    return count;
}

- (id)getNoticeCountModelWithType:(NSInteger)type {
    id model = %orig;
    id group = nil;
    id count = nil;
    @try {
        group = [model valueForKey:@"group"];
        count = [model valueForKey:@"count"];
    } @catch (NSException *exception) {
    }
    dx_logOnce([NSString stringWithFormat:@"t:%ld", (long)type],
               [NSString stringWithFormat:@"countModel type=%ld group=%@ count=%@", (long)type, group, count]);
    return model;
}

- (NSInteger)calculateTotalCountForGroups:(NSArray *)groups {
    NSInteger count = %orig;
    dx_logOnce([NSString stringWithFormat:@"T:%@", groups],
               [NSString stringWithFormat:@"totalForGroups %@ = %ld", groups, (long)count]);
    return count;
}

- (NSInteger)unreadCountOfFilter:(NSInteger)filter {
    NSInteger count = %orig;
    if (count > 0) {
        dx_logOnce([NSString stringWithFormat:@"f:%ld", (long)filter],
                   [NSString stringWithFormat:@"unreadFilter %ld = %ld", (long)filter, (long)count]);
    }
    return count;
}

- (NSInteger)unreadCountWithShowTypeNumOfFilter:(NSInteger)filter {
    NSInteger count = %orig;
    if (count > 0) {
        dx_logOnce([NSString stringWithFormat:@"fs:%ld", (long)filter],
                   [NSString stringWithFormat:@"unreadFilterShow %ld = %ld", (long)filter, (long)count]);
    }
    return count;
}

- (NSInteger)unreadCountOnlyShowTypeRedDotOfFilter:(NSInteger)filter {
    NSInteger count = %orig;
    if (count > 0) {
        dx_logOnce([NSString stringWithFormat:@"fr:%ld", (long)filter],
                   [NSString stringWithFormat:@"unreadFilterRedDot %ld = %ld", (long)filter, (long)count]);
    }
    return count;
}

- (id)unreadData:(unsigned long long)arg {
    id result = %orig;
    dx_logOnce([NSString stringWithFormat:@"u:%llu", arg],
               [NSString stringWithFormat:@"unreadData %llu = %@", arg, result]);
    return result;
}

- (id)unreadData:(unsigned long long)arg context:(id)context {
    id result = %orig;
    dx_logOnce([NSString stringWithFormat:@"uc:%llu", arg],
               [NSString stringWithFormat:@"unreadDataCtx %llu = %@", arg, result]);
    return result;
}

%end
%end

%ctor {
    if (objc_getClass("TTKNoticeUnreadCountManager") != nil) {
        %init(G_UnreadProbe);
    }
}
