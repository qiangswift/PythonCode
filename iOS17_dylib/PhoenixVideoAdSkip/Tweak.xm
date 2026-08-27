#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static BOOL PVAIsShopMallController(UIViewController *controller) {
    if (!controller) return NO;

    NSString *className = NSStringFromClass(controller.class);
    NSString *title = controller.tabBarItem.title ?: controller.title;
    if ([className rangeOfString:@"ShopMall" options:NSCaseInsensitiveSearch].location != NSNotFound ||
        [title isEqualToString:@"商城"]) {
        return YES;
    }

    if ([controller isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (UINavigationController *)controller;
        for (UIViewController *child in navigation.viewControllers) {
            if (PVAIsShopMallController(child)) return YES;
        }
    }
    return NO;
}

static NSArray *PVAViewControllersWithoutShopMall(NSArray *controllers) {
    if (![controllers isKindOfClass:NSArray.class] || controllers.count == 0) return controllers;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:controllers.count];
    for (id candidate in controllers) {
        if ([candidate isKindOfClass:UIViewController.class] &&
            PVAIsShopMallController((UIViewController *)candidate)) {
            continue;
        }
        [filtered addObject:candidate];
    }
    return filtered.count == controllers.count ? controllers : filtered.copy;
}

// Phoenix Video 7.2.1 routes probabilistic episode-transition ads through
// its own in-video patch-ad service. Refuse at the service eligibility check
// so the ad view and its seven-second skip countdown are never started.
%hook SSBizVideoInVideoPatchAdServiceImp

- (BOOL)canShowAd {
    return NO;
}

%end

// Filter the shop controller while Phoenix constructs its type/index maps.
// Its UITabBarController then lays the remaining four items out evenly.
%hook SSTabBarController

- (NSArray *)tabBarVCs {
    NSArray *original = %orig;
    return PVAViewControllersWithoutShopMall(original);
}

- (void)setViewControllers:(NSArray<__kindof UIViewController *> *)viewControllers animated:(BOOL)animated {
    %orig(PVAViewControllersWithoutShopMall(viewControllers), animated);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UITabBarController *tabController = (UITabBarController *)self;
    NSArray *filtered = PVAViewControllersWithoutShopMall(tabController.viewControllers);
    if (filtered.count != tabController.viewControllers.count) {
        [tabController setViewControllers:filtered animated:NO];
        if (tabController.selectedIndex >= filtered.count) tabController.selectedIndex = 0;
    }
}

%end
