#import "TikTokHeaders.h"
#import "common.h"
#import "Settings/ViewController.h"
#import <objc/runtime.h>
#import <os/log.h>

//
//  Adds a DouX settings entry point to the profile "≡" menu.
//
//  TikTok's profile menu is a TTKC component tree (RootComponent / ContentComponent /
//  SectionComponent) rendered inside TTKProfileMenuFloatingPanelContainer, with
//  TTKProfileMenuViewController as the page. We can't inject a native row (items are
//  server-keyed to fixed components), so we add our own gear control and hook both the
//  page VC and the floating panel container, de-duplicating via a view tag.
//

@interface TTKProfileMenuViewController : UIViewController
@end

@interface TTKProfileMenuFloatingPanelContainer : UIView
@end

@interface DXMenuActionTarget : NSObject
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, strong) UIViewController *presented;
- (void)openDouxSettings;
- (void)dismissDouxSettings;
@end

static os_log_t profile_menu_log;
static const NSInteger kDouXButtonTag = 0xD0C5;

@implementation DXMenuActionTarget

- (void)openDouxSettings {
    UIViewController *host = self.host;
    if (host == nil) {
        host = topMostController();
    }
    if (host == nil) {
        return;
    }

    ViewController *settings = [[ViewController alloc] init];
    UIBarButtonItem *done = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        target:self
        action:@selector(dismissDouxSettings)];
    settings.navigationItem.rightBarButtonItem = done;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    self.presented = nav;
    [host presentViewController:nav animated:YES completion:nil];
}

- (void)dismissDouxSettings {
    [self.host dismissViewControllerAnimated:YES completion:nil];
    self.presented = nil;
}

@end

static DXMenuActionTarget *dx_targetForViewController(UIViewController *host) {
    DXMenuActionTarget *target = [DXMenuActionTarget new];
    target.host = host;
    return target;
}

static UIButton *dx_makeGearButton(void) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    button.tag = kDouXButtonTag;
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.25];
    button.layer.cornerRadius = 18.0;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

static BOOL dx_alreadyAdded(UIView *hostView) {
    if ([hostView viewWithTag:kDouXButtonTag] != nil) {
        return YES;
    }
    UIWindow *window = hostView.window;
    if (window != nil && [window viewWithTag:kDouXButtonTag] != nil) {
        return YES;
    }
    return NO;
}

static void dx_addFloatingButton(UIView *hostView, UIViewController *hostVC) {
    if (hostView == nil || dx_alreadyAdded(hostView)) {
        return;
    }

    DXMenuActionTarget *target = dx_targetForViewController(hostVC);
    UIButton *button = dx_makeGearButton();
    [button addTarget:target action:@selector(openDouxSettings) forControlEvents:UIControlEventTouchUpInside];

    [hostView addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.topAnchor constant:10.0],
        [button.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor constant:-12.0],
        [button.widthAnchor constraintEqualToConstant:36.0],
        [button.heightAnchor constraintEqualToConstant:36.0]
    ]];
    [hostView bringSubviewToFront:button];

    os_log_info(profile_menu_log, "profileMenu: floating gear added to %{public}s", class_getName([hostView class]));
}

%hook TTKProfileMenuViewController

- (void)viewDidLoad {
    %orig;

    if (self.navigationController != nil) {
        if (self.navigationItem.rightBarButtonItem == nil) {
            DXMenuActionTarget *target = dx_targetForViewController(self);
            UIButton *custom = dx_makeGearButton();
            custom.frame = CGRectMake(0, 0, 32, 32);
            [custom addTarget:target action:@selector(openDouxSettings) forControlEvents:UIControlEventTouchUpInside];
            UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:custom];
            item.accessibilityLabel = @"DouX settings";
            self.navigationItem.rightBarButtonItem = item;
            os_log_info(profile_menu_log, "profileMenu: nav gear added");
        }
    } else {
        dx_addFloatingButton(self.view, self);
    }
}

%end

%hook TTKProfileMenuFloatingPanelContainer

- (void)didMoveToWindow {
    %orig;
    dx_addFloatingButton(self, nil);
}

- (void)layoutSubviews {
    %orig;
    dx_addFloatingButton(self, nil);
}

%end

%ctor {
    profile_menu_log = os_log_create("com.kunihir0.doux", "ProfileMenu");
}
