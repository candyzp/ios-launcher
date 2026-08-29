#import "RootViewController.h"
#import "Utils.h"
#import "VerifyInstall.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface RootViewController (DownloadConfigGuardPrivate)
- (void)verifyGame;
@end

@implementation RootViewController (DownloadConfigGuard)

- (BOOL)elf_hasValidDownloadConfiguration {
    NSString *keyPart1 = @"__KEY_PART1__";
    NSString *keyPart2 = @"__KEY_PART2__";
    NSString *encryptedDownload = @"__DOWNLOAD_LINK__";

    if (keyPart1.length == 0 || keyPart2.length == 0 || encryptedDownload.length == 0) {
        return NO;
    }
    if ([keyPart1 containsString:@"__KEY_PART1__"] ||
        [keyPart2 containsString:@"__KEY_PART2__"] ||
        [encryptedDownload containsString:@"__DOWNLOAD_LINK__"]) {
        return NO;
    }

    NSData *keyURLData = [[NSData alloc] initWithBase64EncodedString:keyPart2 options:0];
    if (keyURLData.length == 0) return NO;

    NSString *keyURLString = [[NSString alloc] initWithData:keyURLData encoding:NSUTF8StringEncoding];
    NSURLComponents *components = [NSURLComponents componentsWithString:keyURLString];
    NSString *scheme = components.scheme.lowercaseString;
    if (!components || components.host.length == 0 ||
        !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) {
        return NO;
    }

    NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedDownload options:0];
    return encryptedData.length > 0;
}

- (void)elf_showMissingDownloadConfiguration {
    [self.launchButton setEnabled:YES];
    [UIApplication sharedApplication].idleTimerDisabled = NO;

    NSLog(@"[DownloadConfigGuard] Missing or invalid GD download build secrets; using verify/import fallback");

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Download setup missing"
        message:@"This build does not contain a valid Geometry Dash download configuration. Use Verify / Import to provide your own Geometry Dash installation instead."
        preferredStyle:UIAlertControllerStyleAlert];

    __weak RootViewController *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Verify / Import"
                                             style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *action) {
        RootViewController *strongSelf = weakSelf;
        if (strongSelf) [strongSelf verifyGame];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:^(__unused UIAlertAction *action) {
        [weakSelf updateState];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)elf_guard_downloadGame {
    // Non-sandboxed installs and the normal Geode-only install path do not use
    // the encrypted Geometry Dash download URL, so leave them untouched.
    if (![Utils isSandboxed] || [VerifyInstall verifyGDInstalled]) {
        [self elf_guard_downloadGame];
        return;
    }

    if (![self elf_hasValidDownloadConfiguration]) {
        [self elf_showMissingDownloadConfiguration];
        return;
    }

    [self elf_guard_downloadGame];
}

@end

__attribute__((constructor)) static void InstallDownloadConfigGuard(void) {
    Method originalMethod = class_getInstanceMethod(RootViewController.class, @selector(downloadGame));
    Method replacementMethod = class_getInstanceMethod(RootViewController.class, @selector(elf_guard_downloadGame));
    if (originalMethod && replacementMethod) {
        method_exchangeImplementations(originalMethod, replacementMethod);
    } else {
        NSLog(@"[DownloadConfigGuard] Failed to install download guard");
    }
}
