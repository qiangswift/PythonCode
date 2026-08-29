#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

static BOOL RABHideLaunchContainer(UIView *view) {
    if (!view) return NO;
    BOOL found = NO;
    if ([NSStringFromClass(view.class) isEqualToString:@"UIAdBgView"]) {
        view.hidden = YES;
        view.alpha = 0;
        view.userInteractionEnabled = NO;
        found = YES;
    }
    for (UIView *child in view.subviews) {
        if (RABHideLaunchContainer(child)) found = YES;
    }
    return found;
}

// Keep the complete launch-ad lifecycle intact and hide only its final UIKit
// container after it has been attached to a window. No 12306 private method is
// replaced, avoiding the launch crashes seen with AdvertisService/BonSplashAD.
%hook UIWindow
- (void)addSubview:(UIView *)view {
    %orig;
    RABHideLaunchContainer(view);
}
%end

// Keep the native home banner and its layout intact, but prevent its private
// timer from advancing to the next item. The initially rendered item remains
// visible and manual UIKit layout/interaction is otherwise untouched.
%hook MTBookTicketHomeTopADView
- (void)initAnimationScrollTimerWithDuration:(CGFloat)duration {
}

- (void)startScroll {
}
%end

static void RABInstallWebRules(WKWebView *webView) {
    static NSString *script =
        @"(function(){"
         "if(window.__rails12306AdBlockV3Installed){return 'present';}"
         "window.__rails12306AdBlockV3Installed=true;"
         "function hideAds(){"
           "var nodes=document.querySelectorAll('.order-recommend-advertisement-wrap,#app>.added-services-contain~*,.top-ad-class,.train-mall');"
           "for(var i=0;i<nodes.length;i++){"
             "nodes[i].style.setProperty('display','none','important');"
             "nodes[i].style.setProperty('height','0','important');"
             "nodes[i].style.setProperty('min-height','0','important');"
             "nodes[i].style.setProperty('margin','0','important');"
             "nodes[i].style.setProperty('padding','0','important');"
           "}"
           "return nodes.length;"
         "}"
         "var count=hideAds();"
         "var root=document.documentElement||document;"
         "new MutationObserver(hideAds).observe(root,{childList:true,subtree:true});"
         "return 'installed:'+count;"
        "})()";
    [webView evaluateJavaScript:script completionHandler:nil];
}

static void RABProcessView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:WKWebView.class]) RABInstallWebRules((WKWebView *)view);
    for (UIView *child in view.subviews) RABProcessView(child);
}

static void RABRunSafePass(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                RABHideLaunchContainer(window);
                RABProcessView(window);
            }
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ RABRunSafePass(); });
    });
}

%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ RABRunSafePass(); });
    }
}
