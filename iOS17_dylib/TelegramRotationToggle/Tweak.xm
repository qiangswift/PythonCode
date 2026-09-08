#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static NSString *const CRTLockedKey = @"com.swiftss.telegramrotationtoggle.locked";
static const void *CRTButtonKey = &CRTButtonKey;
static IMP CRTOriginalDelegateMask = NULL;
static Class CRTHookedDelegateClass = Nil;

static BOOL CRTIsLocked(void) {
    return [NSUserDefaults.standardUserDefaults boolForKey:CRTLockedKey];
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
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
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

static void CRTInstallButton(UIViewController *controller) {
    if (!controller.isViewLoaded || !controller.view.window) return;
    UIButton *button = objc_getAssociatedObject(controller, CRTButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tintColor = UIColor.labelColor;
        button.imageView.contentMode = UIViewContentModeScaleAspectFit;
        button.accessibilityIdentifier = @"com.swiftss.telegramrotationtoggle.button";
        [button addTarget:controller action:@selector(crt_toggleRotationLock)
            forControlEvents:UIControlEventTouchUpInside];
        [controller.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.widthAnchor constraintEqualToConstant:40.0],
            [button.heightAnchor constraintEqualToConstant:40.0],
            [button.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor
                constant:2.0],
            [button.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor
                constant:-52.0]
        ]];
        objc_setAssociatedObject(controller, CRTButtonKey, button,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [controller.view bringSubviewToFront:button];
    CRTUpdateButton(button);
}

%hook UIApplication
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    if (CRTIsLocked()) return UIInterfaceOrientationMaskPortrait;
    return %orig;
}
%end

%hook UIViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (CRTIsLocked()) return UIInterfaceOrientationMaskPortrait;
    return %orig;
}

- (BOOL)shouldAutorotate {
    if (CRTIsLocked()) return NO;
    return %orig;
}
%end

%hook _TtC10TelegramUI18ChatControllerImpl
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    CRTInstallButton((UIViewController *)self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    UIButton *button = objc_getAssociatedObject(self, CRTButtonKey);
    UIViewController *controller = (UIViewController *)self;
    if (button) [controller.view bringSubviewToFront:button];
}

%new
- (void)crt_toggleRotationLock {
    BOOL locked = !CRTIsLocked();
    [NSUserDefaults.standardUserDefaults setBool:locked forKey:CRTLockedKey];
    UIButton *button = objc_getAssociatedObject(self, CRTButtonKey);
    if (button) CRTUpdateButton(button);
    CRTRefreshOrientation();
}
%end

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"ph.telegra.Telegraph"] &&
            ![bundle isEqualToString:@"app.swiftgram.ios"]) return;
        [NSNotificationCenter.defaultCenter
            addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                CRTHookApplicationDelegate();
                if (CRTIsLocked()) CRTRefreshOrientation();
            }];
    }
}
