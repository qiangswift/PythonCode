#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>

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

static BOOL PVAIsShopMallTitle(NSString *title) {
    return [title isKindOfClass:NSString.class] && [title isEqualToString:@"商城"];
}

static NSString *PVATabNameForType(id controller, NSNumber *type) {
    SEL selector = NSSelectorFromString(@"getTabbarItemNameWithType:");
    if (![controller respondsToSelector:selector] || ![type respondsToSelector:@selector(intValue)]) return nil;
    return ((id (*)(id, SEL, int))objc_msgSend)(controller, selector, type.intValue);
}

static NSArray *PVATypeArrayWithoutShopMall(id controller, NSArray *types) {
    if (![types isKindOfClass:NSArray.class]) return types;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:types.count];
    for (NSNumber *type in types) {
        if (PVAIsShopMallTitle(PVATabNameForType(controller, type))) continue;
        [filtered addObject:type];
    }
    return filtered.count == types.count ? types : filtered.copy;
}

static UILabel *PVAFindShopMallLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class] && PVAIsShopMallTitle(((UILabel *)view).text)) {
        return (UILabel *)view;
    }
    for (UIView *child in view.subviews) {
        UILabel *result = PVAFindShopMallLabel(child);
        if (result) return result;
    }
    return nil;
}

static void PVACleanupVisibleShopMallTab(UITabBarController *tabController) {
    NSArray<UIViewController *> *controllers = tabController.viewControllers;
    if (controllers.count <= 4) return;

    NSInteger shopIndex = NSNotFound;
    NSArray<UITabBarItem *> *items = tabController.tabBar.items;
    NSUInteger comparableCount = MIN(items.count, controllers.count);
    for (NSUInteger index = 0; index < comparableCount; index++) {
        if (PVAIsShopMallTitle(items[index].title)) {
            shopIndex = (NSInteger)index;
            break;
        }
    }

    if (shopIndex == NSNotFound) {
        UILabel *label = PVAFindShopMallLabel(tabController.tabBar);
        if (label && tabController.tabBar.bounds.size.width > 0) {
            CGPoint center = [label.superview convertPoint:label.center toView:tabController.tabBar];
            CGFloat segmentWidth = tabController.tabBar.bounds.size.width / controllers.count;
            shopIndex = MIN((NSInteger)controllers.count - 1, MAX(0, (NSInteger)floor(center.x / segmentWidth)));
        }
    }

    if (shopIndex == NSNotFound || shopIndex >= (NSInteger)controllers.count) return;
    NSMutableArray *remaining = controllers.mutableCopy;
    [remaining removeObjectAtIndex:(NSUInteger)shopIndex];
    [tabController setViewControllers:remaining animated:NO];
    if (tabController.selectedIndex >= remaining.count) tabController.selectedIndex = 0;

    SEL resetSelector = NSSelectorFromString(@"resetTabBarRatio");
    if ([tabController respondsToSelector:resetSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(tabController, resetSelector);
    }
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

- (NSArray *)typeArray {
    NSArray *original = %orig;
    return PVATypeArrayWithoutShopMall(self, original);
}

- (BOOL)isTabBarItemVisible:(int)itemType {
    if (PVAIsShopMallTitle(PVATabNameForType(self, @(itemType)))) return NO;
    return %orig;
}

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
    dispatch_async(dispatch_get_main_queue(), ^{
        PVACleanupVisibleShopMallTab(tabController);
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    PVACleanupVisibleShopMallTab((UITabBarController *)self);
}

%end
