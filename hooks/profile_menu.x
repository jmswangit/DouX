#import "TikTokHeaders.h"
#import "common.h"
#import "Settings/ViewController.h"
#import <objc/runtime.h>
#import <os/log.h>

//
//  Adds a DouX settings entry point to the profile "≡" menu.
//
//  TikTok's profile menu is composed of server-keyed cell models (settings_and_privacy,
//  qr_code, ...) that map to fixed local components, so a custom row can't be injected
//  reliably. Instead we hook the menu's view controller and add our own control: a
//  navigation-bar gear when it lives in a navigation controller, otherwise a small
//  floating gear in the top-right corner of the menu panel.
//

@interface TTKProfileMenuViewController : UIViewController
@end

@interface DXMenuActionTarget : NSObject
@property (nonatomic, weak) UIViewController *host;
@property (nonatomic, strong) UIViewController *presented;
- (void)openDouxSettings;
- (void)dismissDouxSettings;
@end

static os_log_t profile_menu_log;
static const void *kDouXMenuButtonKey = &kDouXMenuButtonKey;
static const void *kDouXTargetKey = &kDouXTargetKey;

@implementation DXMenuActionTarget

- (void)openDouxSettings {
    UIViewController *host = self.host;
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

static UIBarButtonItem *dx_makeMenuBarButton(UIViewController *host) {
    DXMenuActionTarget *target = [DXMenuActionTarget new];
    target.host = host;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    button.frame = CGRectMake(0, 0, 32, 32);
    [button addTarget:target action:@selector(openDouxSettings) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, kDouXTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:button];
    item.accessibilityLabel = @"DouX settings";
    return item;
}

static void dx_addFloatingMenuButton(UIViewController *host) {
    DXMenuActionTarget *target = [DXMenuActionTarget new];
    target.host = host;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
    button.tintColor = [UIColor labelColor];
    button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.25];
    button.layer.cornerRadius = 18.0;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:target action:@selector(openDouxSettings) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, kDouXTargetKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *container = host.view;
    [container addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.topAnchor constant:8.0],
        [button.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12.0],
        [button.widthAnchor constraintEqualToConstant:36.0],
        [button.heightAnchor constraintEqualToConstant:36.0]
    ]];
    objc_setAssociatedObject(container, kDouXMenuButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook TTKProfileMenuViewController

- (void)viewDidLoad {
    %orig;

    if (self.navigationController != nil) {
        if (self.navigationItem.rightBarButtonItem == nil) {
            self.navigationItem.rightBarButtonItem = dx_makeMenuBarButton(self);
        }
    } else if (objc_getAssociatedObject(self, kDouXMenuButtonKey) == nil) {
        dx_addFloatingMenuButton(self);
    }

    os_log_info(profile_menu_log, "profileMenu: DouX entry added");
}

%end

%ctor {
    profile_menu_log = os_log_create("com.kunihir0.doux", "ProfileMenu");
}
