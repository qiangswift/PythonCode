#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const TSDEnabledKey = @"com.swiftss.telegramsystemdns.enabled";
static const void *TSDPanelKey = &TSDPanelKey;
static const void *TSDSettingsButtonKey = &TSDSettingsButtonKey;
static IMP TSDOriginalResolveUniversal = NULL;
static BOOL TSDDNSHookInstalled = NO;

static BOOL TSDIsEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:TSDEnabledKey];
}

static id TSDValueForKey(id object, NSString *key) {
    if (!object) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL TSDClassNameContains(id object, NSString *fragment) {
    return object && [NSStringFromClass([object class]) containsString:fragment];
}

static UIViewController *TSDTelegramRootController(UIViewController *controller) {
    for (UIViewController *current = controller; current; current = current.parentViewController) {
        if (TSDClassNameContains(current, @"TelegramRootController")) return current;
        if (TSDClassNameContains(current.navigationController, @"TelegramRootController")) {
            return current.navigationController;
        }
    }
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) {
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    for (UIWindow *window in windows) {
        NSMutableArray<UIViewController *> *queue = [NSMutableArray array];
        if (window.rootViewController) [queue addObject:window.rootViewController];
        while (queue.count != 0) {
            UIViewController *current = queue.firstObject;
            [queue removeObjectAtIndex:0];
            if (TSDClassNameContains(current, @"TelegramRootController")) return current;
            if (current.presentedViewController) [queue addObject:current.presentedViewController];
            [queue addObjectsFromArray:current.childViewControllers];
        }
    }
    return nil;
}

static void TSDOpenTelegramSettings(UIViewController *source) {
    UIViewController *root = TSDTelegramRootController(source);
    id tabController = TSDValueForKey(root, @"rootTabController");
    id settingsController = TSDValueForKey(root, @"accountSettingsController");
    NSArray *controllers = TSDValueForKey(tabController, @"controllers");
    NSUInteger index = [controllers indexOfObjectIdenticalTo:settingsController];
    SEL selector = NSSelectorFromString(@"setSelectedIndex:");
    if (index != NSNotFound && [tabController respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(tabController, selector, (NSInteger)index);
    }
}

static BOOL TSDIsHomeController(UIViewController *controller) {
    return TSDClassNameContains(controller, @"ChatListControllerImpl");
}

static BOOL TSDIsSearchText(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *lower = text.lowercaseString;
    return [lower containsString:@"search"] || [text containsString:@"搜索"];
}

static void TSDHideSearchControls(UIView *view, UIView *rootView) {
    for (UIView *child in view.subviews) {
        CGRect frame = [child convertRect:child.bounds toView:rootView];
        NSString *label = child.accessibilityLabel;
        if (TSDIsSearchText(label) && CGRectGetMidY(frame) < rootView.safeAreaInsets.top + 90.0) {
            child.hidden = YES;
        } else {
            TSDHideSearchControls(child, rootView);
        }
    }
}

static BOOL TSDIsTabTitle(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    static NSSet<NSString *> *titles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titles = [NSSet setWithArray:@[@"contacts", @"calls", @"chats", @"settings",
            @"联系人", @"通讯录", @"通话", @"聊天", @"设置"]];
    });
    return [titles containsObject:text.lowercaseString];
}

static void TSDCollectTabLabels(UIView *view, UIView *rootView, NSMutableArray<UIView *> *result) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UILabel.class] && TSDIsTabTitle(((UILabel *)child).text)) {
            CGRect frame = [child convertRect:child.bounds toView:rootView];
            if (CGRectGetMidY(frame) > CGRectGetHeight(rootView.bounds) - 130.0) {
                [result addObject:child];
            }
        }
        TSDCollectTabLabels(child, rootView, result);
    }
}

static UIView *TSDCommonAncestor(UIView *first, UIView *second) {
    NSMutableSet<NSValue *> *ancestors = [NSMutableSet set];
    for (UIView *view = first; view; view = view.superview) {
        [ancestors addObject:[NSValue valueWithNonretainedObject:view]];
    }
    for (UIView *view = second; view; view = view.superview) {
        if ([ancestors containsObject:[NSValue valueWithNonretainedObject:view]]) return view;
    }
    return nil;
}

static void TSDHideBottomTabBar(UIViewController *controller) {
    UIViewController *root = TSDTelegramRootController(controller);
    id tabController = TSDValueForKey(root, @"rootTabController");
    UIView *rootView = [tabController isKindOfClass:UIViewController.class]
        ? ((UIViewController *)tabController).view : nil;
    if (!rootView) return;

    NSMutableArray<UIView *> *labels = [NSMutableArray array];
    TSDCollectTabLabels(rootView, rootView, labels);
    if (labels.count < 2) return;
    UIView *common = TSDCommonAncestor(labels[0], labels[1]);
    for (NSUInteger i = 2; common && i < labels.count; i++) {
        common = TSDCommonAncestor(common, labels[i]);
    }
    if (!common || common == rootView) return;
    CGRect frame = [common convertRect:common.bounds toView:rootView];
    if (CGRectGetHeight(frame) <= 150.0 && CGRectGetMaxY(frame) >= CGRectGetHeight(rootView.bounds) - 10.0) {
        common.hidden = YES;
        common.userInteractionEnabled = NO;
    }
}

@interface TSDHomeTarget : NSObject
@property (nonatomic, weak) UIViewController *controller;
- (void)openSettings:(id)sender;
@end

@implementation TSDHomeTarget
- (void)openSettings:(id)sender {
    TSDOpenTelegramSettings(self.controller);
}
@end


static void TSDInstallHomeButton(UIViewController *controller) {
    if (!TSDIsHomeController(controller) || !controller.view.window) return;
    TSDHideSearchControls(controller.view, controller.view);
    TSDHideBottomTabBar(controller);

    UIButton *button = objc_getAssociatedObject(controller, TSDSettingsButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tintColor = UIColor.labelColor;
        UIImage *image = [UIImage systemImageNamed:@"plus" withConfiguration:
            [UIImageSymbolConfiguration configurationWithPointSize:23.0 weight:UIImageSymbolWeightRegular]];
        [button setImage:image forState:UIControlStateNormal];
        button.accessibilityLabel = @"Settings";
        TSDHomeTarget *target = [TSDHomeTarget new];
        target.controller = controller;
        [button addTarget:target action:@selector(openSettings:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(button, @selector(openSettings:), target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [controller.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-8.0],
            [button.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:2.0],
            [button.widthAnchor constraintEqualToConstant:44.0],
            [button.heightAnchor constraintEqualToConstant:44.0]
        ]];
        objc_setAssociatedObject(controller, TSDSettingsButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    button.hidden = NO;
    [controller.view bringSubviewToFront:button];
}

static id TSDResolveUniversal(id self, SEL selector, NSString *hostname, int32_t port) {
    if (TSDIsEnabled()) {
        SEL nativeSelector = NSSelectorFromString(@"resolveHostnameNative:port:");
        if ([self respondsToSelector:nativeSelector]) {
            return ((id (*)(id, SEL, NSString *, int32_t))objc_msgSend)(
                self, nativeSelector, hostname, port);
        }
    }
    return ((id (*)(id, SEL, NSString *, int32_t))TSDOriginalResolveUniversal)(
        self, selector, hostname, port);
}

static void TSDInstallDNSHook(void) {
    if (TSDDNSHookInstalled) return;
    Class dnsClass = NSClassFromString(@"MTDNS");
    if (!dnsClass) return;

    SEL selector = NSSelectorFromString(@"resolveHostnameUniversal:port:");
    Method method = class_getClassMethod(dnsClass, selector);
    if (!method) return;

    MSHookMessageEx(object_getClass(dnsClass), selector, (IMP)TSDResolveUniversal,
        &TSDOriginalResolveUniversal);
    TSDDNSHookInstalled = TSDOriginalResolveUniversal != NULL;
}

static BOOL TSDTextLooksLikeProxyTitle(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *value = [text stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0) return NO;
    NSString *lower = value.lowercaseString;
    return [lower isEqualToString:@"proxy"] ||
        [lower isEqualToString:@"proxy settings"] ||
        [value isEqualToString:@"代理"] ||
        [value isEqualToString:@"代理设置"] ||
        [value isEqualToString:@"代理伺服器"] ||
        [value isEqualToString:@"代理伺服器設定"];
}

static BOOL TSDViewContainsTopProxyTitle(UIView *view, UIView *rootView) {
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:UILabel.class] &&
            TSDTextLooksLikeProxyTitle(((UILabel *)child).text)) {
            CGRect frame = [child convertRect:child.bounds toView:rootView];
            if (CGRectGetMidY(frame) <= rootView.safeAreaInsets.top + 70.0) return YES;
        }
        if (TSDViewContainsTopProxyTitle(child, rootView)) return YES;
    }
    return NO;
}

static BOOL TSDIsProxyController(UIViewController *controller) {
    NSString *title = controller.title;
    NSString *navigationTitle = controller.navigationItem.title;
    if (title.length != 0 || navigationTitle.length != 0) {
        return TSDTextLooksLikeProxyTitle(title) ||
            TSDTextLooksLikeProxyTitle(navigationTitle);
    }
    return controller.isViewLoaded &&
        TSDViewContainsTopProxyTitle(controller.view, controller.view);
}

@interface TSDPanel : UIControl
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *noticeLabel;
@property (nonatomic, strong) UISwitch *toggle;
@end

@implementation TSDPanel
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.layer.cornerRadius = 12.0;
    self.layer.cornerCurve = kCACornerCurveContinuous;

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.text = @"Use system DNS";
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _noticeLabel = [UILabel new];
    _noticeLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    _noticeLabel.textColor = UIColor.secondaryLabelColor;
    _noticeLabel.numberOfLines = 2;
    _noticeLabel.text = @"Use the iOS DNS resolver for proxy hostnames. Useful when Google DNS is unavailable.";
    _noticeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    _toggle = [UISwitch new];
    _toggle.on = TSDIsEnabled();
    _toggle.translatesAutoresizingMaskIntoConstraints = NO;
    [_toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];

    [self addSubview:_titleLabel];
    [self addSubview:_noticeLabel];
    [self addSubview:_toggle];
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16.0],
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:12.0],
        [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggle.leadingAnchor constant:-12.0],
        [_toggle.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14.0],
        [_toggle.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [_noticeLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
        [_noticeLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [_noticeLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:5.0]
    ]];
    self.accessibilityIdentifier = @"com.swiftss.telegramsystemdns.panel";
    return self;
}

- (void)toggleChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:TSDEnabledKey];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event];
}
@end

static void TSDRemovePanel(UIViewController *controller) {
    TSDPanel *panel = objc_getAssociatedObject(controller, TSDPanelKey);
    if (panel) {
        [panel removeFromSuperview];
        objc_setAssociatedObject(controller, TSDPanelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void TSDInstallPanel(UIViewController *controller) {
    if (!controller.view.window || !TSDIsProxyController(controller)) {
        TSDRemovePanel(controller);
        return;
    }
    TSDPanel *panel = objc_getAssociatedObject(controller, TSDPanelKey);
    if (!panel) {
        panel = [[TSDPanel alloc] initWithFrame:CGRectZero];
        panel.translatesAutoresizingMaskIntoConstraints = NO;
        [controller.view addSubview:panel];
        [NSLayoutConstraint activateConstraints:@[
            [panel.leadingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.leadingAnchor constant:16.0],
            [panel.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0],
            [panel.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],
            [panel.heightAnchor constraintEqualToConstant:76.0]
        ]];
        objc_setAssociatedObject(controller, TSDPanelKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    panel.toggle.on = TSDIsEnabled();
    [controller.view bringSubviewToFront:panel];
}

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    TSDInstallPanel(self);
    TSDInstallHomeButton(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    TSDPanel *panel = objc_getAssociatedObject(self, TSDPanelKey);
    if (panel) [self.view bringSubviewToFront:panel];
    if (TSDIsHomeController(self)) TSDInstallHomeButton(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    TSDRemovePanel(self);
    UIButton *button = objc_getAssociatedObject(self, TSDSettingsButtonKey);
    button.hidden = YES;
}
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"ph.telegra.Telegraph"]) return;
        %init;
        TSDInstallDNSHook();
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                TSDInstallDNSHook();
            }];
    }
}
