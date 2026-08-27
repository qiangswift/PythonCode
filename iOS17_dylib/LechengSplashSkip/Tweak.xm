#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static void LCSSendVoidMessage(id object, SEL selector) {
    ((void (*)(id, SEL))objc_msgSend)(object, selector);
}

// Lecheng 8.12.1 uses separate controllers for its online/API splash and
// cached fallback splash. Trigger each controller's own close action after
// view setup so its delegate and startup transition still run normally.
%hook LCAPIADViewController

- (void)viewDidLoad {
    ((UIViewController *)self).view.hidden = YES;
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        LCSSendVoidMessage(self, @selector(skipAdBtnClick));
    });
}

%end

%hook LCAdLoadViewController

- (void)viewDidLoad {
    ((UIViewController *)self).view.hidden = YES;
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        LCSSendVoidMessage(self, @selector(cancelAdBtnClick));
    });
}

%end

// Use the device preview page's own visibility decisions so the surrounding
// content is laid out as if the value-added-service banner did not exist.
%hook _TtC15LCIphoneAdhocIP23LCPMediaPreviewDiffImpl

- (BOOL)isServiceBannerShowWithMediaState:(id)mediaState {
    return NO;
}

- (BOOL)needCheckShowCloudStorageBanner {
    return NO;
}

%end
