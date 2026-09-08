#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <substrate.h>

static NSString *const CRTLockedKey = @"com.swiftss.telegramrotationtoggle.locked";
static IMP CRTOriginalDelegateMask = NULL;
static Class CRTHookedDelegateClass = Nil;
static BOOL CRTChatHooksInstalled = NO;
static void (*CRTOriginalChatViewDidAppear)(id, SEL, BOOL) = NULL;
static void (*CRTOriginalChatViewDidLayoutSubviews)(id, SEL) = NULL;

@interface CRTPassthroughWindow : UIWindow
@property (nonatomic, weak) UIButton *touchButton;
@end

@implementation CRTPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIButton *button = self.touchButton;
    if (!button || button.hidden || !button.userInteractionEnabled) return nil;
    CGPoint buttonPoint = [button convertPoint:point fromView:self];
    if (![button pointInside:buttonPoint withEvent:event]) return nil;
    return [button hitTest:buttonPoint withEvent:event] ?: button;
}
@end

@interface CRTRotationToggleTarget : NSObject
- (void)toggle:(UIButton *)sender;
@end

static CRTRotationToggleTarget *CRTActionTarget = nil;
static CRTPassthroughWindow *CRTOverlayWindow = nil;

static BOOL CRTIsLocked(void) {
    id storedValue = [NSUserDefaults.standardUserDefaults objectForKey:CRTLockedKey];
    return storedValue ? [storedValue boolValue] : YES;
}

static NSString *CRTResourcePath(NSString *name) {
    Dl_info info = {0};
    if (!dladdr((const void *)&CRTResourcePath, &info) || !info.dli_fname) return nil;
    NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
    NSRange marker = [dylibPath rangeOfString:@"/Library/MobileSubstrate/DynamicLibraries/"];
    if (marker.location == NSNotFound) return nil;
    NSString *prefix = [dylibPath substringToIndex:marker.location];
    return [prefix stringByAppendingPathComponent:
        [@"Library/Application Support/TelegramRotationToggle" stringByAppendingPathComponent:name]];
}

static UIImage *CRTIcon(BOOL locked) {
    NSString *path = CRTResourcePath(locked ? @"locked.png" : @"unlocked.png");
    UIImage *image = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!image) {
        image = [UIImage systemImageNamed:locked ? @"lock.fill" : @"lock.open.fill"];
    }
    if (image && (image.size.width > 28.0 || image.size.height > 28.0)) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc]
            initWithSize:CGSizeMake(22.0, 22.0)];
        image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [image drawInRect:CGRectMake(0.0, 0.0, 22.0, 22.0)];
        }];
    }
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static BOOL CRTIsChatController(id controller) {
    return [NSStringFromClass([controller class])
        isEqualToString:@"_TtC10TelegramUI18ChatControllerImpl"];
}

static UIInterfaceOrientationMask CRTDelegateMask(id self, SEL selector,
    UIApplication *application, UIWindow *window) {
    if (CRTIsLocked()) return UIInterfaceOrientationMaskPortrait;
    if (CRTOriginalDelegateMask) {
        return ((UIInterfaceOrientationMask (*)(id, SEL, UIApplication *, UIWindow *))
            CRTOriginalDelegateMask)(self, selector, application, window);
    }
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

static void CRTHookApplicationDelegate(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    if (!delegate) return;
    Class cls = object_getClass(delegate);
    if (!cls || cls == CRTHookedDelegateClass) return;

    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : "Q@:@@";
    if (method) CRTOriginalDelegateMask = method_getImplementation(method);
    class_replaceMethod(cls, selector, (IMP)CRTDelegateMask, types);
    CRTHookedDelegateClass = cls;
}

static void CRTRefreshOrientation(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CRTHookApplicationDelegate();
        UIInterfaceOrientationMask mask = CRTIsLocked()
            ? UIInterfaceOrientationMaskPortrait
            : UIInterfaceOrientationMaskAllButUpsideDown;

        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *scene = (UIWindowScene *)candidate;
            if (@available(iOS 16.0, *)) {
                for (UIWindow *window in scene.windows) {
                    [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
                }
                Class preferencesClass = NSClassFromString(@"UIWindowSceneGeometryPreferencesIOS");
                SEL initSelector = NSSelectorFromString(@"initWithInterfaceOrientations:");
                SEL requestSelector = NSSelectorFromString(@"requestGeometryUpdateWithPreferences:errorHandler:");
                if (preferencesClass && [scene respondsToSelector:requestSelector]) {
                    id preferences = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                        [preferencesClass alloc], initSelector, mask);
                    ((void (*)(id, SEL, id, id))objc_msgSend)(scene, requestSelector,
                        preferences, ^(NSError *error) {});
                }
            }
        }
        [UIViewController attemptRotationToDeviceOrientation];
    });
}

static void CRTUpdateButton(UIButton *button) {
    BOOL locked = CRTIsLocked();
    UIImage *icon = CRTIcon(locked);
    if (icon) [button setImage:icon forState:UIControlStateNormal];
    button.accessibilityLabel = locked ? @"启用随重力旋转" : @"锁定竖屏";
    button.accessibilityValue = locked ? @"当前已锁定" : @"当前可旋转";
}

@implementation CRTRotationToggleTarget
- (void)toggle:(UIButton *)sender {
    BOOL locked = !CRTIsLocked();
    [NSUserDefaults.standardUserDefaults setBool:locked forKey:CRTLockedKey];
    CRTUpdateButton(sender);
    CRTRefreshOrientation();
}
@end

static void CRTInstallButton(UIViewController *controller) {
    UIWindowScene *scene = controller.view.window.windowScene;
    if (!scene) return;

    if (!CRTOverlayWindow || CRTOverlayWindow.windowScene != scene) {
        CRTOverlayWindow.hidden = YES;
        CRTOverlayWindow = [[CRTPassthroughWindow alloc] initWithWindowScene:scene];
        CRTOverlayWindow.windowLevel = UIWindowLevelAlert - 1.0;
        CRTOverlayWindow.backgroundColor = UIColor.clearColor;

        UIViewController *overlayController = [UIViewController new];
        overlayController.view.backgroundColor = UIColor.clearColor;
        CRTOverlayWindow.rootViewController = overlayController;

        if (!CRTActionTarget) CRTActionTarget = [CRTRotationToggleTarget new];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tintColor = UIColor.labelColor;
        button.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.92];
        button.layer.cornerRadius = 20.0;
        button.clipsToBounds = YES;
        button.accessibilityIdentifier = @"com.swiftss.telegramrotationtoggle.button";
        [button addTarget:CRTActionTarget action:@selector(toggle:)
            forControlEvents:UIControlEventTouchUpInside];
        [overlayController.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:40.0],
            [button.heightAnchor constraintEqualToConstant:40.0],
            [button.topAnchor constraintEqualToAnchor:
                overlayController.view.safeAreaLayoutGuide.topAnchor constant:2.0],
            [button.trailingAnchor constraintEqualToAnchor:
                overlayController.view.safeAreaLayoutGuide.trailingAnchor
                constant:-66.0]
        ]];
        CRTOverlayWindow.touchButton = button;
    }

    UIButton *button = CRTOverlayWindow.touchButton;
    button.hidden = NO;
    CRTUpdateButton(button);
    CRTOverlayWindow.hidden = NO;
}

static void CRTChatViewDidAppear(id self, SEL selector, BOOL animated) {
    if (CRTOriginalChatViewDidAppear) {
        CRTOriginalChatViewDidAppear(self, selector, animated);
    }
    CRTInstallButton((UIViewController *)self);
}

static void CRTChatViewDidLayoutSubviews(id self, SEL selector) {
    if (CRTOriginalChatViewDidLayoutSubviews) {
        CRTOriginalChatViewDidLayoutSubviews(self, selector);
    }
    CRTInstallButton((UIViewController *)self);
}

static void CRTHookChatControllerIfAvailable(void) {
    if (CRTChatHooksInstalled) return;
    Class chatClass = NSClassFromString(@"_TtC10TelegramUI18ChatControllerImpl");
    if (!chatClass) return;

    MSHookMessageEx(chatClass, @selector(viewDidAppear:),
        (IMP)CRTChatViewDidAppear, (IMP *)&CRTOriginalChatViewDidAppear);
    MSHookMessageEx(chatClass, @selector(viewDidLayoutSubviews),
        (IMP)CRTChatViewDidLayoutSubviews,
        (IMP *)&CRTOriginalChatViewDidLayoutSubviews);
    CRTChatHooksInstalled = YES;
}

static void CRTImageAdded(const struct mach_header *header, intptr_t slide) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CRTHookChatControllerIfAvailable();
    });
}

%hook UIApplication
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if (CRTIsLocked()) return UIInterfaceOrientationMaskPortrait;
    return %orig;
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (CRTIsChatController(self)) {
        CRTInstallButton(self);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (CRTIsChatController(self)) {
        CRTInstallButton(self);
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (CRTIsChatController(self)) {
        CRTOverlayWindow.hidden = YES;
    }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (CRTIsLocked()) return UIInterfaceOrientationMaskPortrait;
    return %orig;
}

- (BOOL)shouldAutorotate {
    if (CRTIsLocked()) return NO;
    return %orig;
}
%end

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"ph.telegra.Telegraph"] &&
            ![bundle isEqualToString:@"app.swiftgram.ios"]) return;
        %init;
        _dyld_register_func_for_add_image(CRTImageAdded);
        CRTHookChatControllerIfAvailable();
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                CRTHookApplicationDelegate();
                CRTHookChatControllerIfAvailable();
                if (CRTIsLocked()) CRTRefreshOrientation();
            }];
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                CRTHookApplicationDelegate();
                CRTHookChatControllerIfAvailable();
                if (CRTIsLocked()) CRTRefreshOrientation();
            }];
    }
}
