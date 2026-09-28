#import "TikTokHeaders.h"
#import "Settings/ViewController.h"
#import "common.h"

static NSString *const kDouXSettingsIdentifier = @"doux_settings";

static AWESettingItemModel *dx_makeItemModel(void) {
    AWESettingItemModel *model = [[%c(AWESettingItemModel) alloc] initWithIdentifier:kDouXSettingsIdentifier];
    [model setTitle:@"DouX settings"];
    [model setDetail:@"DouX settings"];
    [model setIconImage:[UIImage systemImageNamed:@"gear"]];
    [model setType:99];
    return model;
}

static TTKSettingsBaseCellPlugin *dx_makePlugin(id context) {
    if (context == nil) {
        return nil;
    }
    TTKSettingsBaseCellPlugin *plugin = [[%c(TTKSettingsBaseCellPlugin) alloc] initWithPluginContext:context];
    [plugin setItemModel:dx_makeItemModel()];
    return plugin;
}

static BOOL dx_isDouxPlugin(id object) {
    if (![object respondsToSelector:@selector(itemModel)]) {
        return NO;
    }
    id model = [object itemModel];
    if (![model respondsToSelector:@selector(identifier)]) {
        return NO;
    }
    return [[model identifier] isEqualToString:kDouXSettingsIdentifier];
}

static BOOL dx_arrayHasDouxPlugin(NSArray *array) {
    if (![array isKindOfClass:[NSArray class]]) {
        return NO;
    }
    for (id object in array) {
        if (dx_isDouxPlugin(object)) {
            return YES;
        }
    }
    return NO;
}

static void dx_openDouxSettings(void) {
    UINavigationController *settings = [[UINavigationController alloc] initWithRootViewController:[[ViewController alloc] init]];
    [topMostController() presentViewController:settings animated:true completion:nil];
}

%hook TTKSettingsBaseCellPlugin
- (void)didSelectItemAtIndex:(NSInteger)index {
    if ([self.itemModel.identifier isEqualToString:kDouXSettingsIdentifier]) {
        dx_openDouxSettings();
    } else {
        return %orig;
    }
}
%end

%hook AWESettingsNormalSectionViewModel

- (void)viewDidLoad {
    %orig;
    if ([self.sectionIdentifier isEqualToString:@"account"] && self.context != nil && !dx_arrayHasDouxPlugin(self.modelsArray)) {
        TTKSettingsBaseCellPlugin *plugin = dx_makePlugin(self.context);
        if (plugin != nil) {
            [self insertModel:plugin atIndex:0 animated:true];
        }
    }
}

//
// The settings page assigns its models after viewDidLoad and re-assigns them whenever the
// list refreshes, which is why the row used to flash then vanish. Re-inject on every
// assignment so it survives reloads.
//
- (void)setModelsArray:(NSArray *)modelsArray {
    if ([self.sectionIdentifier isEqualToString:@"account"] && ![dx_arrayHasDouxPlugin(modelsArray)]) {
        TTKSettingsBaseCellPlugin *plugin = dx_makePlugin(self.context);
        if (plugin != nil) {
            NSMutableArray *updated = modelsArray != nil ? [modelsArray mutableCopy] : [NSMutableArray array];
            [updated insertObject:plugin atIndex:0];
            %orig(updated);
            return;
        }
    }
    %orig;
}

%end
