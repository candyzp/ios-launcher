#import "EnterpriseCompare.h"
#import "RootViewController.h"
#import "SettingsVC.h"
#import "Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Enterprise launch compatibility fixes.
//
// 1. RootViewController's patch-check URL is currently built as:
//      ?checksum=<hash>count=<n>&args=...
//    so NSURLComponents treats "count=<n>" as part of the checksum value.
//    The Helper then always sees a checksum mismatch and falls back to its
//    gray error window instead of launching Geometry Dash.
//
// 2. "Launch without patching" is useful as a recovery path, but the setting
//    is unnecessarily disabled unless the entire Developer Mode is enabled.
//    Keep the setting scoped to Enterprise Mode while making that one button
//    usable for everyone.

@interface Setting (EnterpriseLaunchFixFactory)
+ (instancetype)create:(NSString *)title
                  type:(SettingType)type
              disabled:(BOOL (^)(void))disabled
               visible:(BOOL (^)(void))visible
              prefsKey:(NSString *)prefsKey
             switchTag:(NSInteger)switchTag
                action:(void (^)(void))action
                custom:(void (^)(UITableViewCell *cell))custom;
@end

@implementation RootViewController (EnterpriseLaunchFix)

- (void)elf_launchHelper2:(BOOL)safeMode patchCheck:(BOOL)patchCheck {
    // Preserve the original implementation for the explicit no-patch path.
    // After swizzling, elf_launchHelper2:patchCheck: points to the original.
    if (!patchCheck) {
        [self elf_launchHelper2:safeMode patchCheck:NO];
        return;
    }

    NSString *env = nil;
    NSString *launchArgs = [[Utils getPrefs] stringForKey:@"LAUNCH_ARGS"];
    if (launchArgs.length > 2) {
        env = launchArgs;
    } else if (safeMode) {
        env = @"--geode:use-common-handler-offset=8c4000 --geode:safe-mode";
    } else {
        env = @"--geode:use-common-handler-offset=8c4000";
    }

    NSString *b64 = [[env dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    NSMutableString *encodedArgs = [b64 mutableCopy];
    [encodedArgs replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, encodedArgs.length)];
    [encodedArgs replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, encodedArgs.length)];
    while ([encodedArgs hasSuffix:@"="]) {
        [encodedArgs deleteCharactersInRange:NSMakeRange(encodedArgs.length - 1, 1)];
    }

    NSString *checksum = [EnterpriseCompare getChecksum:NO];
    NSInteger modCount = [EnterpriseCompare getModCount:NO];

    // If checksum generation itself fails, use the existing no-patch recovery
    // route instead of creating a broken URL containing "(null)".
    if (checksum.length == 0) {
        NSLog(@"[EnterpriseLaunchFix] Missing checksum; launching Helper without patch check");
        [self elf_launchHelper2:safeMode patchCheck:NO];
        return;
    }

    NSString *maxFPS = [[Utils getPrefs] boolForKey:@"USE_MAX_FPS"] ? @"&cahighfps=1" : @"";

    // IMPORTANT: '&count=' is intentional. The original source is missing
    // this ampersand, corrupting the checksum query item.
    NSString *openURL = [NSString stringWithFormat:
        @"geode-helper://launch?checksum=%@&count=%ld&args=%@%@",
        checksum,
        (long)modCount,
        encodedArgs,
        maxFPS
    ];

    NSURL *url = [NSURL URLWithString:openURL];
    if (!url || ![[UIApplication sharedApplication] canOpenURL:url]) {
        NSLog(@"[EnterpriseLaunchFix] Geode Helper URL cannot be opened: %@", openURL);
        [self.launchButton setEnabled:YES];

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Error"
            message:@"Geode Helper couldn't be launched. Please verify that the Helper is installed."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSLog(@"[EnterpriseLaunchFix] Launching Helper with checksum=%@ count=%ld", checksum, (long)modCount);
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.launchButton setEnabled:YES];
            });
        }
    }];
}

@end

@implementation Setting (EnterpriseLaunchFix)

+ (instancetype)elf_create:(NSString *)title
                      type:(SettingType)type
                  disabled:(BOOL (^)(void))disabled
                   visible:(BOOL (^)(void))visible
                  prefsKey:(NSString *)prefsKey
                 switchTag:(NSInteger)switchTag
                    action:(void (^)(void))action
                    custom:(void (^)(UITableViewCell *cell))custom {
    if ([title isEqualToString:@"Launch without patching"]) {
        disabled = nil;
    }

    // After swizzling, this selector points to Setting's original factory.
    return [self elf_create:title
                       type:type
                   disabled:disabled
                    visible:visible
                   prefsKey:prefsKey
                  switchTag:switchTag
                     action:action
                     custom:custom];
}

@end

__attribute__((constructor)) static void InstallEnterpriseLaunchFix(void) {
    Method originalLaunch = class_getInstanceMethod(
        RootViewController.class,
        @selector(launchHelper2:patchCheck:)
    );
    Method fixedLaunch = class_getInstanceMethod(
        RootViewController.class,
        @selector(elf_launchHelper2:patchCheck:)
    );
    if (originalLaunch && fixedLaunch) {
        method_exchangeImplementations(originalLaunch, fixedLaunch);
    } else {
        NSLog(@"[EnterpriseLaunchFix] Failed to install launchHelper2 fix");
    }

    Method originalCreate = class_getClassMethod(
        Setting.class,
        @selector(create:type:disabled:visible:prefsKey:switchTag:action:custom:)
    );
    Method fixedCreate = class_getClassMethod(
        Setting.class,
        @selector(elf_create:type:disabled:visible:prefsKey:switchTag:action:custom:)
    );
    if (originalCreate && fixedCreate) {
        method_exchangeImplementations(originalCreate, fixedCreate);
    } else {
        NSLog(@"[EnterpriseLaunchFix] Failed to unlock Launch without patching");
    }
}
