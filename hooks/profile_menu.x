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

static os_log_t profile_menu_log;
static const void *kDouXMenuButtonKey = &kDouXMenuButtonKey;

static void dx_presentDouxSettings(UIViewController *from) {
    ViewController *settings = [[ViewController alloc] init];

    UIBarButtonItem *done = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
        primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
            [from dismissViewControllerAnimated:YES completion:nil];
        }]];
    settings.navigationItem.rightBarButtonItem = done;

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    [from presentViewController:nav animated:YES completion:nil];
}

%hook TTKProfileMenuViewController

- (void)viewDidLoad {
    %orig;

    if (objc_getAssociatedObject(self, kDouXMenuButtonKey) != nil) {
        return;
    }

    UIImage *icon = [UIImage systemImageNamed:@"gearshape.fill"];

    if (self.navigationController != nil) {
        UIBarButtonItem *item = [[UIBarButtonItem alloc]
            initWithImage:icon
            primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
                dx_presentDouxSettings(self);
            }]];
        item.accessibilityLabel = @"DouX settings";
        self.navigationItem.rightBarButtonItem = item;
        objc_setAssociatedObject(self, kDouXMenuButtonKey, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setImage:icon forState:UIControlStateNormal];
        button.tintColor = [UIColor labelColor];
        button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.25];
        button.layer.cornerRadius = 18.0;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        [button addAction:[UIAction actionWithHandler:^(UIAction *action) {
            dx_presentDouxSettings(self);
        }] forControlEvents:UIControlEventTouchUpInside];

        UIView *host = self.view;
        [host addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:8.0],
            [button.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-12.0],
            [button.widthAnchor constraintEqualToConstant:36.0],
            [button.heightAnchor constraintEqualToConstant:36.0]
        ]];
        objc_setAssociatedObject(self, kDouXMenuButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    os_log_info(profile_menu_log, "profileMenu: DouX entry added");
}

%end

%ctor {
    profile_menu_log = os_log_create("com.kunihir0.doux", "ProfileMenu");
}
