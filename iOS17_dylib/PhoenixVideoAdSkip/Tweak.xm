#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>

static NSString *const kPVALogName = @"PhoenixVideoAdSkip.log";

static void PVALog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [documents stringByAppendingPathComponent:kPVALogName];
    NSData *data = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message] dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { [data writeToFile:path atomically:YES]; return; }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile]; [handle writeData:data]; [handle closeFile];
}

static BOOL PVAIsShopMallTitle(NSString *title) {
    if (![title isKindOfClass:NSString.class]) return NO;
    return [title isEqualToString:@"商城"] || [title caseInsensitiveCompare:@"mall"] == NSOrderedSame;
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

static UIView *PVAClosestTabButton(UIView *view, UIView *root) {
    UIView *candidate = view;
    while (candidate && candidate != root) {
        if ([candidate isKindOfClass:UIControl.class]) return candidate;
        candidate = candidate.superview;
    }
    return PVADirectChildContainingView(view, root);
}

static NSString *PVATabName(id controller, id type) {
    SEL selector = NSSelectorFromString(@"getTabbarItemNameWithType:");
    if (![controller respondsToSelector:selector] || ![type respondsToSelector:@selector(intValue)]) return nil;
    return ((id (*)(id, SEL, int))objc_msgSend)(controller, selector, [type intValue]);
}

static UIView *PVATabButton(id controller, id type) {
    SEL selector = NSSelectorFromString(@"getTabBarItemButtonWithType:");
    if (![controller respondsToSelector:selector] || ![type respondsToSelector:@selector(intValue)]) return nil;
    id button = ((id (*)(id, SEL, int))objc_msgSend)(controller, selector, [type intValue]);
    return [button isKindOfClass:UIView.class] ? button : nil;
}

static void PVADumpTabInventory(id controller) {
    SEL typeSelector = NSSelectorFromString(@"typeArray");
    NSArray *types = [controller respondsToSelector:typeSelector] ? ((id (*)(id, SEL))objc_msgSend)(controller, typeSelector) : nil;
    PVALog(@"TAB inventory types=%@", types);
    for (id type in types) {
        UIView *button = PVATabButton(controller, type);
        PVALog(@"TAB type=%@ name=%@ button=%@ frame=%@ hidden=%d", type, PVATabName(controller, type),
               NSStringFromClass(button.class), NSStringFromCGRect(button.frame), button.hidden);
    }
}

static void PVACleanupVisibleShopMallTab(UITabBarController *tabController) {
    UIView *root = nil;
    SEL visibleSelector = NSSelectorFromString(@"topVisibleTabBar");
    if ([tabController respondsToSelector:visibleSelector]) {
        root = ((id (*)(id, SEL))objc_msgSend)(tabController, visibleSelector);
    }
    if (![root isKindOfClass:UIView.class]) root = tabController.tabBar;

    UILabel *shopLabel = PVAFindShopMallLabel(root);
    UIView *shopContainer = PVAClosestTabButton(shopLabel, root);

    SEL typeSelector = NSSelectorFromString(@"typeArray");
    NSArray *types = [(id)tabController respondsToSelector:typeSelector] ? ((id (*)(id, SEL))objc_msgSend)(tabController, typeSelector) : nil;
    NSMutableArray<UIView *> *nativeButtons = [NSMutableArray array];
    for (id type in types) {
        UIView *nativeButton = PVATabButton(tabController, type);
        if (nativeButton && ![nativeButtons containsObject:nativeButton]) [nativeButtons addObject:nativeButton];
        if (PVAIsShopMallTitle(PVATabName(tabController, type)) && nativeButton) shopContainer = nativeButton;
    }

    if (shopContainer && nativeButtons.count >= 5) {
        [nativeButtons sortUsingComparator:^NSComparisonResult(UIView *left, UIView *right) {
            CGFloat leftX = CGRectGetMinX(left.frame), rightX = CGRectGetMinX(right.frame);
            return leftX < rightX ? NSOrderedAscending : (leftX > rightX ? NSOrderedDescending : NSOrderedSame);
        }];
        shopContainer.hidden = YES;
        shopContainer.userInteractionEnabled = NO;
        [nativeButtons removeObject:shopContainer];
        CGFloat availableWidth = CGRectGetMaxX(((UIView *)nativeButtons.lastObject).frame);
        if (availableWidth <= 0) availableWidth = root.bounds.size.width;
        CGFloat width = availableWidth / nativeButtons.count;
        for (NSUInteger index = 0; index < nativeButtons.count; index++) {
            UIView *button = nativeButtons[index];
            button.hidden = NO;
            button.userInteractionEnabled = YES;
            CGRect frame = button.frame;
            frame.origin.x = width * index;
            frame.size.width = width;
            button.frame = frame;
        }
        PVALog(@"TAB native mall hidden type=5 remaining=%@ width=%.2f", nativeButtons, width);
        return;
    }
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
    PVALog(@"TAB hide shop class=%@ frame=%@ root=%@", NSStringFromClass(shopContainer.class),
           NSStringFromCGRect(shopContainer.frame), NSStringFromClass(root.class));
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
    PVADumpTabInventory(self);
    dispatch_async(dispatch_get_main_queue(), ^{
        PVACleanupVisibleShopMallTab(tabController);
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    PVACleanupVisibleShopMallTab((UITabBarController *)self);
}

%end

%ctor {
    @autoreleasepool {
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.phoenix.video"]) {
            PVALog(@"START version=1.1.4 native mall removal");
        }
    }
}
