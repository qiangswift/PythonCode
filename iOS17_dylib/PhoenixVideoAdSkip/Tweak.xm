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

static UIView *PVADirectChildContainingView(UIView *view, UIView *root) {
    UIView *candidate = view;
    while (candidate.superview && candidate.superview != root) candidate = candidate.superview;
    return candidate.superview == root ? candidate : nil;
}

static void PVACollectTitleContainers(UIView *view, UIView *root, NSMutableArray<UIView *> *containers) {
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length > 0) {
        UIView *container = PVADirectChildContainingView(view, root);
        if (container && ![containers containsObject:container]) [containers addObject:container];
    }
    for (UIView *child in view.subviews) PVACollectTitleContainers(child, root, containers);
}

static void PVACleanupVisibleShopMallTab(UITabBarController *tabController) {
    UIView *root = nil;
    SEL visibleSelector = NSSelectorFromString(@"topVisibleTabBar");
    if ([tabController respondsToSelector:visibleSelector]) {
        root = ((id (*)(id, SEL))objc_msgSend)(tabController, visibleSelector);
    }
    if (![root isKindOfClass:UIView.class]) root = tabController.tabBar;

    UILabel *shopLabel = PVAFindShopMallLabel(root);
    UIView *shopContainer = PVADirectChildContainingView(shopLabel, root);
    if (!shopContainer || root.bounds.size.width <= 0) return;

    NSMutableArray<UIView *> *allContainers = [NSMutableArray array];
    PVACollectTitleContainers(root, root, allContainers);
    CGFloat shopMidY = CGRectGetMidY(shopContainer.frame);
    NSPredicate *sameRow = [NSPredicate predicateWithBlock:^BOOL(UIView *candidate, NSDictionary *bindings) {
        return fabs(CGRectGetMidY(candidate.frame) - shopMidY) < 24.0 && candidate.bounds.size.width > 20.0;
    }];
    NSMutableArray<UIView *> *row = [[allContainers filteredArrayUsingPredicate:sameRow] mutableCopy];
    [row sortUsingComparator:^NSComparisonResult(UIView *left, UIView *right) {
        CGFloat leftX = CGRectGetMinX(left.frame), rightX = CGRectGetMinX(right.frame);
        return leftX < rightX ? NSOrderedAscending : (leftX > rightX ? NSOrderedDescending : NSOrderedSame);
    }];
    if (row.count < 5 || ![row containsObject:shopContainer]) return;

    shopContainer.hidden = YES;
    shopContainer.userInteractionEnabled = NO;
    [row removeObject:shopContainer];
    CGFloat width = root.bounds.size.width / row.count;
    for (NSUInteger index = 0; index < row.count; index++) {
        UIView *button = row[index];
        button.hidden = NO;
        button.userInteractionEnabled = YES;
        CGRect frame = button.frame;
        frame.origin.x = width * index;
        frame.size.width = width;
        button.frame = frame;
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
    return %orig;
}

- (BOOL)isTabBarItemVisible:(int)itemType {
    return %orig;
}

- (NSArray *)tabBarVCs {
    return %orig;
}

- (void)setViewControllers:(NSArray<__kindof UIViewController *> *)viewControllers animated:(BOOL)animated {
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UITabBarController *tabController = (UITabBarController *)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        PVACleanupVisibleShopMallTab(tabController);
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    PVACleanupVisibleShopMallTab((UITabBarController *)self);
}

%end
