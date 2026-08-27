#import <Foundation/Foundation.h>

// China Mobile 12.5.2 already implements a complete native skip path in
// CMStartViewController. Force only its own decision method and leave the
// controller's startup/transition callbacks untouched.
%hook CMStartViewController

- (BOOL)isNeedSkipStartAd {
    return YES;
}

%end
