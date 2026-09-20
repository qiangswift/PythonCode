#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const TSDEnabledKey = @"com.swiftss.telegramsystemdns.enabled";
static const void *TSDPanelKey = &TSDPanelKey;
static IMP TSDOriginalResolveUniversal = NULL;
static BOOL TSDDNSHookInstalled = NO;

static BOOL TSDIsEnabled(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:TSDEnabledKey];
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
}

- (void)viewDidLayoutSubviews {
    %orig;
    TSDPanel *panel = objc_getAssociatedObject(self, TSDPanelKey);
    if (panel) [self.view bringSubviewToFront:panel];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    TSDRemovePanel(self);
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
