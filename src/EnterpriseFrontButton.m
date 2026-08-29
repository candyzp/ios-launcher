#import "RootViewController.h"
#import "Theming.h"
#import "Utils.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static char kEnterpriseNoPatchButtonKey;

@implementation RootViewController (EnterpriseFrontButton)

- (UIButton *)elf_frontNoPatchButton {
    return objc_getAssociatedObject(self, &kEnterpriseNoPatchButtonKey);
}

- (void)elf_setFrontNoPatchButton:(UIButton *)button {
    objc_setAssociatedObject(self, &kEnterpriseNoPatchButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)elf_refreshFrontNoPatchButton {
    UIButton *button = [self elf_frontNoPatchButton];
    if (!button) return;

    BOOL enterpriseMode = [[Utils getPrefs] boolForKey:@"ENTERPRISE_MODE"];
    button.hidden = !enterpriseMode;
    button.enabled = enterpriseMode;

    if (!enterpriseMode || !self.launchButton) return;

    CGFloat width = MIN(240.0, self.view.bounds.size.width - 40.0);
    CGFloat height = 40.0;
    CGFloat x = (self.view.bounds.size.width - width) / 2.0;
    CGFloat y = CGRectGetMaxY(self.launchButton.frame) + 10.0;
    button.frame = CGRectMake(x, y, width, height);

    button.layer.cornerRadius = height / 2.0;
    button.backgroundColor = [Theming getDarkColor];
    [button setTitleColor:[Theming getWhiteColor] forState:UIControlStateNormal];
    button.tintColor = [Theming getWhiteColor];
}

- (void)elf_frontNoPatchTapped {
    [self.impactFeedback impactOccurred];
    [self.impactFeedback prepare];

    // This intentionally uses the exact same no-patch path exposed in Settings.
    [self launchHelper2:NO patchCheck:NO];
}

- (void)elf_front_viewDidLoad {
    [self elf_front_viewDidLoad];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"Launch without patching" forState:UIControlStateNormal];
    [button setImage:[[UIImage systemImageNamed:@"forward.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
            forState:UIControlStateNormal];
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 7, 0, 0);
    button.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 7);
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    button.accessibilityIdentifier = @"enterpriseLaunchWithoutPatchingButton";
    [button addTarget:self action:@selector(elf_frontNoPatchTapped) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:button];
    [self elf_setFrontNoPatchButton:button];
    [self elf_refreshFrontNoPatchButton];
}

- (void)elf_front_updateState {
    [self elf_front_updateState];
    [self elf_refreshFrontNoPatchButton];
}

- (void)elf_front_viewDidLayoutSubviews {
    [self elf_front_viewDidLayoutSubviews];
    [self elf_refreshFrontNoPatchButton];
}

@end

static void ELFSwizzleInstanceMethod(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method originalMethod = class_getInstanceMethod(cls, originalSelector);
    Method replacementMethod = class_getInstanceMethod(cls, replacementSelector);
    if (originalMethod && replacementMethod) {
        method_exchangeImplementations(originalMethod, replacementMethod);
    } else {
        NSLog(@"[EnterpriseFrontButton] Failed to swizzle %@", NSStringFromSelector(originalSelector));
    }
}

__attribute__((constructor)) static void InstallEnterpriseFrontButton(void) {
    ELFSwizzleInstanceMethod(RootViewController.class, @selector(viewDidLoad), @selector(elf_front_viewDidLoad));
    ELFSwizzleInstanceMethod(RootViewController.class, @selector(updateState), @selector(elf_front_updateState));
    ELFSwizzleInstanceMethod(RootViewController.class, @selector(viewDidLayoutSubviews), @selector(elf_front_viewDidLayoutSubviews));
}
