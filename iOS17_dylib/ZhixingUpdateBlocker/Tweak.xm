#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// These names were recovered from Zhixing 10.19.2's Objective-C metadata.
static BOOL ZTIsBlockedPopupController(UIViewController *controller) {
    if (!controller) return NO;

    NSString *name = NSStringFromClass(controller.class);
    return [name isEqualToString:@"ZTAppUpdateVC"] ||
           [name isEqualToString:@"ZTAppGuideUpdateViewController"] ||
           [name isEqualToString:@"ZTMarketHomePopViewController"] ||
           [name isEqualToString:@"ZTHotelHomePopUpWindowViewController"];
}

static void ZTNoop2(id self, SEL _cmd, id arg1, id arg2) {
    // Intentionally suppress the app's update UI entry point.
}

static void ZTNoop1(id self, SEL _cmd, id arg1) {
    // Intentionally suppress the app's update alert entry point.
}

static void (*ZTOriginalPresent)(UIViewController *, SEL, UIViewController *, BOOL, void (^)(void));

static void ZTHookedPresent(UIViewController *self, SEL _cmd,
                            UIViewController *controller, BOOL animated,
                            void (^completion)(void)) {
    if (ZTIsBlockedPopupController(controller)) {
        // Treat a blocked presentation as completed so callers do not wait.
        if (completion) completion();
        return;
    }
    ZTOriginalPresent(self, _cmd, controller, animated, completion);
}

// Static disassembly of -tripMobAdSplashShowDidDismiss shows that the app's
// splash manager advances the launch flow by invoking actionBlock with event 3.
// Skip only the SDK display call and reproduce that normal dismiss event.
%hook CTAdSdkSplashViewManager

- (void)loadAndDisplayWithKeyWindow:(id)window
                             fromVC:(id)viewController
                        actionBlock:(void (^)(NSInteger event))actionBlock {
    if (!actionBlock) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        actionBlock(3);
    });
}

%end

static BOOL ZTClassOwnsSelector(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == selector) {
            found = YES;
            break;
        }
    }
    free(methods);
    return found;
}

static void ZTHookSelectorOnClass(Class cls, SEL selector, IMP replacement) {
    // Hook only methods implemented by this exact class. Using
    // class_getInstanceMethod here also returns inherited implementations and
    // caused the first release to install the same hook repeatedly.
    if (ZTClassOwnsSelector(cls, selector)) {
        MSHookMessageEx(cls, selector, replacement, NULL);
    }

    Class meta = object_getClass(cls);
    if (meta && ZTClassOwnsSelector(meta, selector)) {
        MSHookMessageEx(meta, selector, replacement, NULL);
    }
}

static void ZTInstallUpdateEntryHooks(void) {
    const struct {
        const char *name;
        IMP replacement;
    } hooks[] = {
        { "zt_showAppGuideUpdateViewControllerWithModel:completion:", (IMP)ZTNoop2 },
        { "zt_showAppUpdateVCWithModel:completion:",                (IMP)ZTNoop2 },
        { "showAppGuideUpdateViewControllerWithModel:completion:",  (IMP)ZTNoop2 },
        { "showAppUpdateVCWithModel:completion:",                   (IMP)ZTNoop2 },
        { "showAppGuideUpdatePopWithCompletion:",                   (IMP)ZTNoop1 },
        { "showAppUpdateAlert:",                                    (IMP)ZTNoop1 },
    };

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) {
        for (size_t j = 0; j < sizeof(hooks) / sizeof(hooks[0]); j++) {
            ZTHookSelectorOnClass(classes[i], sel_registerName(hooks[j].name), hooks[j].replacement);
        }
    }
    free(classes);
}

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
        if (![bundleID isEqualToString:@"cn.suanya.zhixingHC"]) return;

        MSHookMessageEx([UIViewController class],
                        @selector(presentViewController:animated:completion:),
                        (IMP)ZTHookedPresent,
                        (IMP *)&ZTOriginalPresent);

        ZTInstallUpdateEntryHooks();
    }
}
