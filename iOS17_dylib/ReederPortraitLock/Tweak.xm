#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP RPLOriginalDelegateMask = NULL;
static Class RPLHookedDelegateClass = Nil;

static UIInterfaceOrientationMask RPLPortraitMask(id self, SEL selector,
    UIApplication *application, UIWindow *window) {
    return UIInterfaceOrientationMaskPortrait;
}

static void RPLHookDelegate(void) {
    id delegate = UIApplication.sharedApplication.delegate;
    if (!delegate) return;
    Class cls = object_getClass(delegate);
    if (!cls || cls == RPLHookedDelegateClass) return;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod(cls, selector);
    const char *types = method ? method_getTypeEncoding(method) : "Q@:@@";
    if (method) RPLOriginalDelegateMask = method_getImplementation(method);
    class_replaceMethod(cls, selector, (IMP)RPLPortraitMask, types);
    RPLHookedDelegateClass = cls;
    NSLog(@"[ReederPortraitLock] hooked delegate %@", NSStringFromClass(cls));
}

static void RPLRequestPortrait(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        RPLHookDelegate();
        for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
            if (![candidate isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *scene = (UIWindowScene *)candidate;
            if (@available(iOS 16.0, *)) {
                for (UIWindow *window in scene.windows) {
                    [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
                }
                Class cls = NSClassFromString(@"UIWindowSceneGeometryPreferencesIOS");
                SEL initSelector = NSSelectorFromString(@"initWithInterfaceOrientations:");
                SEL requestSelector = NSSelectorFromString(@"requestGeometryUpdateWithPreferences:errorHandler:");
                if (cls && [scene respondsToSelector:requestSelector]) {
                    id preferences = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                        [cls alloc], initSelector, UIInterfaceOrientationMaskPortrait);
                    ((void (*)(id, SEL, id, id))objc_msgSend)(scene, requestSelector, preferences,
                        ^(NSError *error) {
                            NSLog(@"[ReederPortraitLock] geometry request error: %@", error);
                        });
                }
            }
        }
        [UIViewController attemptRotationToDeviceOrientation];
    });
}

%hook UIApplication
- (UIInterfaceOrientationMask)supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskPortrait;
}
%end

%hook UIViewController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}
- (BOOL)shouldAutorotate {
    return NO;
}
%end

%ctor {
    @autoreleasepool {
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                RPLRequestPortrait();
            }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                RPLRequestPortrait();
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                    dispatch_get_main_queue(), ^{ RPLRequestPortrait(); });
            }];
    }
}
