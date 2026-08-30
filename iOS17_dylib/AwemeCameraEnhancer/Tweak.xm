#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

@interface ACCRecordSystemLivePhotoServiceImpl : NSObject
- (void)setEnableSystemLivePhoto:(BOOL)enabled;
- (void)toggleLivePhotoInnerSwitch:(BOOL)enabled;
- (void)reopenSystemLivePhotoRecording;
@end
@interface ACCVideoEditFlowControlComponent : NSObject
- (BOOL)backToShootNeedAlert:(BOOL)needAlert;
@end
@interface AWESettingItemModel : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *detail;
@property(nonatomic) NSInteger type;
@property(nonatomic, copy) NSString *svgIconImageName;
@property(nonatomic) NSInteger cellType;
@property(nonatomic) NSInteger colorStyle;
@property(nonatomic) BOOL isEnable;
@property(nonatomic, copy) void (^cellTappedBlock)(void);
@end
@interface AWESettingSectionModel : NSObject
@property(nonatomic, copy) NSArray *itemArray;
@property(nonatomic) NSInteger type;
@property(nonatomic) CGFloat sectionHeaderHeight;
@property(nonatomic, copy) NSString *sectionHeaderTitle;
@end
@interface AWESettingsViewModel : NSObject
@property(nonatomic, weak) UIViewController *controllerDelegate;
@end
@interface ACECommentInputContainerView : UIView
@end

static const NSTimeInterval kACEMaxRecordDuration = 86400.0;
static NSString *const kACEVideoDefaultKey = @"ACEVideoDefaultEnabled";
static NSString *const kACEUnlimitedDurationKey = @"ACEUnlimitedDurationEnabled";
static NSString *const kACELivePhotoDefaultKey = @"ACELivePhotoDefaultEnabled";
static NSString *const kACEPhotoSaveKey = @"ACEPhotoAutoSaveEnabled";
static NSString *const kACERightButtonsOffsetKey = @"ACERightButtonsVerticalOffset";
static NSString *const kACEDescriptionReflowKey = @"ACEDescriptionReflowEnabled";
static NSString *const kACEDescriptionScaleKey = @"ACEDescriptionFontScale";
static NSString *const kACEDescriptionWeightKey = @"ACEDescriptionFontWeightBoost";
static NSString *const kACENicknameReflowKey = @"ACENicknameReflowEnabled";
static NSString *const kACENicknameScaleKey = @"ACENicknameFontScale";
static NSString *const kACENicknameOffsetKey = @"ACENicknameVerticalOffset";
static NSString *const kACENicknameNoDescriptionOffsetKey = @"ACENicknameNoDescriptionVerticalOffset";
static NSString *const kACEDescriptionOffsetKey = @"ACEDescriptionVerticalOffset";
static __weak UIViewController *gACECameraController;
static __weak ACCRecordSystemLivePhotoServiceImpl *gACESystemLivePhotoService;
static __weak ACCVideoEditFlowControlComponent *gACEEditFlowControl;
static BOOL gACEAwaitingNativeReturn = NO;
static BOOL gACELiveSaveFinished = NO;
static BOOL gACELiveSaveSucceeded = NO;
static BOOL gACELiveSaveInProgress = NO;
static char kACERightStackRegisteredKey;
static char kACEApplyingTransformKey;
static char kACECommentSubviewBaseTransformKey;
static char kACEDescriptionBaseFontKey;
static char kACEDescriptionScaledFontKey;
static char kACEDescriptionBaseAttributedTextKey;
static char kACEDescriptionScaledAttributedTextKey;
static char kACETextElementKindKey;
static char kACEApplyingTextTransformKey;

static id ACEValue(id object, NSString *key);

static BOOL ACEEnabled(NSString *key) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:key] == nil ? YES : [defaults boolForKey:key];
}

#define ACELog(...) do { } while (0)

static CGFloat ACERightButtonsOffset(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:kACERightButtonsOffsetKey] == nil ? 8.0 : [defaults doubleForKey:kACERightButtonsOffsetKey];
}

static CGFloat ACEDescriptionScale(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kACEDescriptionScaleKey];
    CGFloat scale = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.6;
    return MIN(1.0, MAX(0.3, scale));
}

static CGFloat ACEDescriptionWeightBoost(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kACEDescriptionWeightKey];
    CGFloat boost = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.5;
    return MIN(1.0, MAX(0.0, boost));
}

static CGFloat ACENicknameScale(void) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kACENicknameScaleKey];
    CGFloat scale = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 1.0;
    return MIN(1.5, MAX(0.3, scale));
}

static CGFloat ACEVerticalOffset(NSString *key) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    if (!value && [key isEqualToString:kACENicknameNoDescriptionOffsetKey]) {
        value = [NSUserDefaults.standardUserDefaults objectForKey:kACENicknameOffsetKey];
    }
    CGFloat configured = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
    // User-facing convention: positive moves upward; UIKit positive Y is down.
    return -MIN(100.0, MAX(-100.0, configured));
}

static CGFloat ACEConfiguredVerticalOffset(NSString *key) {
    return -ACEVerticalOffset(key);
}

static UIFont *ACEScaledFont(UIFont *font, CGFloat scale, CGFloat weightBoost) {
    if (!font) return nil;
    UIFontDescriptor *descriptor = font.fontDescriptor;
    NSMutableDictionary *traits = [[descriptor objectForKey:UIFontDescriptorTraitsAttribute] mutableCopy] ?: [NSMutableDictionary dictionary];
    CGFloat originalWeight = [traits[UIFontWeightTrait] respondsToSelector:@selector(doubleValue)] ? [traits[UIFontWeightTrait] doubleValue] : UIFontWeightRegular;
    CGFloat boostedWeight = originalWeight + (UIFontWeightBold - originalWeight) * weightBoost;
    traits[UIFontWeightTrait] = @(boostedWeight);
    descriptor = [descriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute: traits}];
    return [UIFont fontWithDescriptor:descriptor size:MAX(6.0, font.pointSize * scale)];
}

static NSAttributedString *ACEScaledAttributedString(NSAttributedString *source, CGFloat scale, CGFloat weightBoost) {
    if (!source.length) return source;
    NSMutableAttributedString *result = [source mutableCopy];
    [source enumerateAttribute:NSFontAttributeName
                       inRange:NSMakeRange(0, source.length)
                       options:0
                    usingBlock:^(UIFont *font, NSRange range, __unused BOOL *stop) {
        if ([font isKindOfClass:UIFont.class]) [result addAttribute:NSFontAttributeName value:ACEScaledFont(font, scale, weightBoost) range:range];
    }];
    return result;
}

static void ACEApplyTextTypographyToView(UIView *view, CGFloat scale, CGFloat weightBoost, BOOL removesTruncation) {
    if (!view) return;

    SEL fontGetter = NSSelectorFromString(@"font");
    SEL fontSetter = NSSelectorFromString(@"setFont:");
    if ([view respondsToSelector:fontGetter] && [view respondsToSelector:fontSetter]) {
        UIFont *current = ((id (*)(id, SEL))objc_msgSend)(view, fontGetter);
        UIFont *base = objc_getAssociatedObject(view, &kACEDescriptionBaseFontKey);
        // Reused feed cells can hand our already-scaled font back during the
        // next layout pass.  Capture the native baseline once; never promote a
        // rendered/scaled font into the baseline or the scale compounds.
        if (!base) {
            base = current;
            if (base) objc_setAssociatedObject(view, &kACEDescriptionBaseFontKey, base, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIFont *scaled = ACEScaledFont(base, scale, weightBoost);
        if (scaled && ![current isEqual:scaled]) {
            objc_setAssociatedObject(view, &kACEDescriptionScaledFontKey, scaled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ((void (*)(id, SEL, id))objc_msgSend)(view, fontSetter, scaled);
        }
    }

    SEL attributedGetter = NSSelectorFromString(@"attributedText");
    SEL attributedSetter = NSSelectorFromString(@"setAttributedText:");
    if ([view respondsToSelector:attributedGetter] && [view respondsToSelector:attributedSetter]) {
        NSAttributedString *current = ((id (*)(id, SEL))objc_msgSend)(view, attributedGetter);
        NSAttributedString *base = objc_getAssociatedObject(view, &kACEDescriptionBaseAttributedTextKey);
        // Attributes are rewritten on every pass, so identity/equality is not
        // a safe signal.  A changed plain string means the reused cell now owns
        // another video and is the only time a new native baseline is accepted.
        BOOL contentChanged = current.length && base.length && ![current.string isEqualToString:base.string];
        if (current.length && (!base || contentChanged)) {
            base = [current copy];
            objc_setAssociatedObject(view, &kACEDescriptionBaseAttributedTextKey, base, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (base.length) {
            NSAttributedString *scaled = ACEScaledAttributedString(base, scale, weightBoost);
            objc_setAssociatedObject(view, &kACEDescriptionScaledAttributedTextKey, scaled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ((void (*)(id, SEL, id))objc_msgSend)(view, attributedSetter, scaled);
        }
    }

    SEL numberSetter = NSSelectorFromString(@"setNumberOfLines:");
    if (removesTruncation && [view respondsToSelector:numberSetter]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(view, numberSetter, 0);
    SEL maximumSetter = NSSelectorFromString(@"setMaximumNumberOfLines:");
    if (removesTruncation && [view respondsToSelector:maximumSetter]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(view, maximumSetter, 0);
    SEL breakSetter = NSSelectorFromString(@"setLineBreakMode:");
    if ([view respondsToSelector:breakSetter]) ((void (*)(id, SEL, NSInteger))objc_msgSend)(view, breakSetter, NSLineBreakByWordWrapping);
    SEL tokenSetter = NSSelectorFromString(@"setTruncationToken:");
    if (removesTruncation && [view respondsToSelector:tokenSetter]) ((void (*)(id, SEL, id))objc_msgSend)(view, tokenSetter, nil);
    SEL widthSetter = NSSelectorFromString(@"setPreferredMaxLayoutWidth:");
    if ([view respondsToSelector:widthSetter] && CGRectGetWidth(view.bounds) > 1.0) {
        ((void (*)(id, SEL, CGFloat))objc_msgSend)(view, widthSetter, CGRectGetWidth(view.bounds));
    }
    [view invalidateIntrinsicContentSize];
    for (UIView *subview in [view.subviews copy]) ACEApplyTextTypographyToView(subview, scale, weightBoost, removesTruncation);
}

static UIView *ACEElementView(id element) {
    UIView *elementView = ACEValue(element, @"elementView");
    if (![elementView isKindOfClass:UIView.class]) elementView = ACEValue(element, @"view");
    return [elementView isKindOfClass:UIView.class] ? elementView : nil;
}

static UIView *ACETextArrangedElementView(UIView *elementView) {
    if (!elementView) return nil;
    Class stackClass = NSClassFromString(@"AWEElementStackView");
    UIView *baseElement = nil;
    Class baseClass = NSClassFromString(@"AWEBaseElementView");
    for (UIView *ancestor = elementView; ancestor; ancestor = ancestor.superview) {
        if (!baseElement && baseClass && [ancestor isKindOfClass:baseClass]) baseElement = ancestor;
        if (stackClass && [ancestor.superview isKindOfClass:stackClass]) return ancestor;
        if (stackClass && [ancestor isKindOfClass:stackClass]) break;
    }
    return baseElement ?: elementView;
}

static BOOL ACEStackHasVisibleDescription(UIView *arrangedView) {
    UIView *stack = arrangedView.superview;
    Class stackClass = NSClassFromString(@"AWEElementStackView");
    if (!stackClass || ![stack isKindOfClass:stackClass]) return NO;
    SEL classNameSelector = NSSelectorFromString(@"elementClassName");
    for (UIView *candidate in [stack.subviews copy]) {
        if (candidate.hidden || candidate.alpha < 0.01 || CGRectGetHeight(candidate.bounds) < 0.5) continue;
        NSString *className = [candidate respondsToSelector:classNameSelector]
            ? ((id (*)(id, SEL))objc_msgSend)(candidate, classNameSelector) : nil;
        if ([className isEqualToString:@"AWEPlayInteractionDescriptionElement"]) return YES;
        if ([NSStringFromClass(candidate.class) containsString:@"Description"]) return YES;
    }
    return NO;
}

static NSString *ACENicknameOffsetKindForTarget(UIView *target) {
    return ACEStackHasVisibleDescription(target) ? @"nickname" : @"nicknameNoDescription";
}

static void ACEApplyTextElementOffset(UIView *target, NSString *kind) {
    if (!target || !kind.length) return;
    NSString *key = [kind isEqualToString:@"nickname"] ? kACENicknameOffsetKey
        : ([kind isEqualToString:@"nicknameNoDescription"] ? kACENicknameNoDescriptionOffsetKey : kACEDescriptionOffsetKey);
    objc_setAssociatedObject(target, &kACETextElementKindKey, kind, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(target, &kACEApplyingTextTransformKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    target.transform = CGAffineTransformMakeTranslation(0, ACEVerticalOffset(key));
    objc_setAssociatedObject(target, &kACEApplyingTextTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ACEApplyDescriptionReflow(id element) {
    if (!ACEEnabled(kACEDescriptionReflowKey)) return;
    UIView *elementView = ACEElementView(element);
    if (!elementView) return;
    UIView *target = ACETextArrangedElementView(elementView);
    ACEApplyTextElementOffset(target, @"description");
    elementView.clipsToBounds = NO;
    ACEApplyTextTypographyToView(elementView, ACEDescriptionScale(), ACEDescriptionWeightBoost(), YES);
    [elementView setNeedsLayout];
    [elementView.superview setNeedsLayout];
}

static void ACEApplyNicknameReflow(id element) {
    if (!ACEEnabled(kACENicknameReflowKey)) return;
    UIView *elementView = ACEElementView(element);
    if (!elementView) return;
    UIView *target = ACETextArrangedElementView(elementView);
    ACEApplyTextElementOffset(target, ACENicknameOffsetKindForTarget(target));
    elementView.clipsToBounds = NO;
    ACEApplyTextTypographyToView(elementView, ACENicknameScale(), 0.0, NO);
    [elementView setNeedsLayout];
    [elementView.superview setNeedsLayout];
}

static void ACEApplyNicknameFollowerOffset(id element) {
    if (!ACEEnabled(kACENicknameReflowKey)) return;
    UIView *elementView = ACEElementView(element);
    if (!elementView) return;
    UIView *target = ACETextArrangedElementView(elementView);
    ACEApplyTextElementOffset(target, ACENicknameOffsetKindForTarget(target));
}

static void ACEApplyNicknameFollowerViewOffset(UIView *followerView) {
    if (!ACEEnabled(kACENicknameReflowKey) || !followerView) return;
    // In Aweme 40.2.0 the recommendation pill's element object does not
    // reliably expose elementView/view.  Start at the concrete pill view so
    // the complete arranged item (including its hit area) is moved.
    UIView *target = ACETextArrangedElementView(followerView);
    ACEApplyTextElementOffset(target, ACENicknameOffsetKindForTarget(target));
}

static NSHashTable<UIView *> *ACERightButtonViews(void) {
    static NSHashTable<UIView *> *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}

static void ACEApplyRightButtonsOffset(UIView *view) {
    if (!view) return;
    [ACERightButtonViews() addObject:view];
    objc_setAssociatedObject(view, &kACERightStackRegisteredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kACEApplyingTransformKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id configuredScale = [NSUserDefaults.standardUserDefaults objectForKey:@"DYYYElementScale"];
    CGFloat scale = [configuredScale respondsToSelector:@selector(doubleValue)] ? [configuredScale doubleValue] : 0;
    if (scale > 0 && fabs(scale - 1.0) > 0.0001) {
        // DYYY rebuilds this transform during every layout. Recreate its scale and
        // alignment compensation, then add our independent screen-point offset.
        view.transform = CGAffineTransformIdentity;
        CGFloat verticalCompensation = 0;
        for (UIView *subview in [view.subviews copy]) {
            CGFloat height = subview.frame.size.height;
            verticalCompensation += (height - height * scale) / 2.0;
        }
        CGFloat width = view.frame.size.width;
        CGFloat horizontalCompensation = (width - width * scale) / 2.0;
        view.transform = CGAffineTransformMake(scale, 0, 0, scale,
                                               horizontalCompensation,
                                               verticalCompensation - ACERightButtonsOffset());
    } else {
        view.transform = CGAffineTransformMakeTranslation(0, -ACERightButtonsOffset());
    }
    objc_setAssociatedObject(view, &kACEApplyingTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIViewController *ACEViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    }
    return nil;
}

static BOOL ACEViewContainsClass(UIView *view, Class targetClass) {
    if (!targetClass) return NO;
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:targetClass] || ACEViewContainsClass(subview, targetClass)) return YES;
    }
    return NO;
}

static BOOL ACEViewBelongsToProfileDetailVideo(UIView *view) {
    Class tableClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    Class cellClass = NSClassFromString(@"AWEAwemeDetailCellViewController");
    UIResponder *responder = view;
    while ((responder = responder.nextResponder)) {
        if ((tableClass && [responder isKindOfClass:tableClass]) ||
            (cellClass && [responder isKindOfClass:cellClass])) return YES;
        if ([responder isKindOfClass:UIViewController.class]) {
            UIViewController *controller = (UIViewController *)responder;
            for (UIViewController *parent = controller.parentViewController; parent; parent = parent.parentViewController) {
                if ((tableClass && [parent isKindOfClass:tableClass]) ||
                    (cellClass && [parent isKindOfClass:cellClass])) return YES;
            }
        }
    }
    return NO;
}

static CGFloat ACEProfileCommentContentCompensation(UIView *view) {
    id configuredHeight = [NSUserDefaults.standardUserDefaults objectForKey:@"DYYYTabBarHeight"];
    CGFloat targetHeight = [configuredHeight respondsToSelector:@selector(doubleValue)] ? [configuredHeight doubleValue] : 0;
    if (targetHeight <= 0 || !ACEViewBelongsToProfileDetailVideo(view)) return 0;
    CGFloat safeAreaBottom = view.window ? view.window.safeAreaInsets.bottom : 0;
    CGFloat downwardOffset = MAX(0, 49.0 + safeAreaBottom - targetHeight);
    return MIN(downwardOffset, safeAreaBottom + 8.0);
}

static void ACECollectSubviewsOfClass(UIView *root, Class targetClass, NSMutableArray<UIView *> *result) {
    if (!targetClass) return;
    for (UIView *subview in [root.subviews copy]) {
        if ([subview isKindOfClass:targetClass]) [result addObject:subview];
        ACECollectSubviewsOfClass(subview, targetClass, result);
    }
}

static void ACEApplyDYYYProfileCommentBarHeight(UIView *view) {
    id configuredHeight = [NSUserDefaults.standardUserDefaults objectForKey:@"DYYYTabBarHeight"];
    CGFloat targetHeight = [configuredHeight respondsToSelector:@selector(doubleValue)] ? [configuredHeight doubleValue] : 0;
    if (targetHeight <= 0 || !ACEViewBelongsToProfileDetailVideo(view)) return;

    CGFloat safeAreaBottom = view.window ? view.window.safeAreaInsets.bottom : 0;
    CGFloat originalHeight = 49.0 + safeAreaBottom;
    CGFloat downwardOffset = MAX(0, originalHeight - targetHeight);
    view.transform = CGAffineTransformMakeTranslation(0, downwardOffset);

    // The Swift container owns both the black background and the controls.
    // Keep the shortened background position, but compensate its content for
    // the home-indicator safe area so labels and action icons remain visible.
    CGFloat contentCompensation = ACEProfileCommentContentCompensation(view);
    Class middleContainerClass = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputViewMiddleContainer");
    NSMutableArray<UIView *> *contentContainers = [NSMutableArray array];
    ACECollectSubviewsOfClass(view, middleContainerClass, contentContainers);
    for (UIView *subview in contentContainers) {
        NSValue *storedTransform = objc_getAssociatedObject(subview, &kACECommentSubviewBaseTransformKey);
        CGAffineTransform baseTransform = storedTransform ? storedTransform.CGAffineTransformValue : subview.transform;
        if (!storedTransform) {
            objc_setAssociatedObject(subview, &kACECommentSubviewBaseTransformKey,
                                     [NSValue valueWithCGAffineTransform:baseTransform],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        subview.transform = CGAffineTransformTranslate(baseTransform, 0, -contentCompensation);
    }
}

static void ACERefreshRightButtonsOffset(void) {
    for (UIView *view in ACERightButtonViews().allObjects) ACEApplyRightButtonsOffset(view);
}

static UIViewController *ACETopController(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) if (candidate.isKeyWindow) { window = candidate; break; }
        if (window) break;
    }
    UIViewController *controller = window.rootViewController;
    while (controller) {
        if (controller.presentedViewController) controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).topViewController;
        else if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
        else break;
    }
    return controller;
}

static void ACETraceCameraEntry(NSString *source) {
    (void)source;
}

static void ACEShowToast(UIViewController *controller, NSString *text) {
    if (!controller.view.window) controller = ACETopController();
    if (!controller.view.window) return;
    UILabel *label = [UILabel new];
    label.text = text; label.textColor = UIColor.whiteColor;
    label.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.86];
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter; label.layer.cornerRadius = 9; label.layer.masksToBounds = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO; [controller.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [label.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor constant:-100],
        [label.heightAnchor constraintEqualToConstant:42], [label.widthAnchor constraintGreaterThanOrEqualToConstant:190]
    ]];
    label.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{ label.alpha = 1; } completion:^(__unused BOOL done) {
        [UIView animateWithDuration:0.25 delay:1.6 options:0 animations:^{ label.alpha = 0; }
                         completion:^(__unused BOOL finished) { [label removeFromSuperview]; }];
    }];
}

static void ACETryNativeReturn(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gACEAwaitingNativeReturn || !gACELiveSaveFinished || !gACEEditFlowControl) return;
        ACCVideoEditFlowControlComponent *flow = gACEEditFlowControl;
        gACEAwaitingNativeReturn = NO;
        BOOL saved = gACELiveSaveSucceeded;
        [flow backToShootNeedAlert:NO];
        gACELiveSaveInProgress = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ACEShowToast(gACECameraController ?: ACETopController(), saved ? @"照片已保存到相册" : @"动态照片保存失败");
        });
    });
}

static id ACEValue(id object, NSString *key) {
    @try { return object ? [object valueForKey:key] : nil; }
    @catch (__unused NSException *exception) { return nil; }
}

static NSURL *ACEFileURL(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = ACEValue(object, key);
        if ([value isKindOfClass:NSURL.class] && ((NSURL *)value).isFileURL) return value;
        if ([value isKindOfClass:NSString.class] && [(NSString *)value length]) {
            NSURL *url = [NSURL fileURLWithPath:value];
            if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) return url;
        }
    }
    return nil;
}

static void ACESaveStatic(UIImage *image) {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{ [PHAssetChangeRequest creationRequestForAssetFromImage:image]; }
                                      completionHandler:^(BOOL success, NSError *error) {
        ACELog(@"PHOTO static saved=%d error=%@", success, error);
        gACELiveSaveSucceeded = success;
        gACELiveSaveFinished = YES;
        ACETryNativeReturn();
    }];
}

static void ACEFinishLiveSave(BOOL success, NSError *error) {
    gACELiveSaveSucceeded = success;
    gACELiveSaveFinished = YES;
    ACELog(@"LIVE_PHOTO paired saved=%d error=%@", success, error);
    ACETryNativeReturn();
}

static void ACEGenerateAndSaveLivePair(NSURL *sourceImage, NSURL *sourceVideo) {
    Class manager = NSClassFromString(@"CAKOnlineResourceManager");
    SEL selector = NSSelectorFromString(@"generateLivePhotoFromStillImage:videoURL:outputDirectory:completion:");
    if (!manager || ![manager respondsToSelector:selector]) {
        ACEFinishLiveSave(NO, [NSError errorWithDomain:@"AwemeCameraEnhancer" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Live Photo generator unavailable"}]);
        return;
    }
    NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"ACE-Live-%@", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *directory = [NSURL fileURLWithPath:folder isDirectory:YES];
    ACELog(@"LIVE_PHOTO generating image=%@ video=%@", sourceImage.path, sourceVideo.path);
    void (^completion)(NSURL *, NSURL *, NSError *) = ^(NSURL *pairedImage, NSURL *pairedVideo, NSError *generationError) {
        if (generationError || !pairedImage.isFileURL || !pairedVideo.isFileURL) {
            ACEFinishLiveSave(NO, generationError ?: [NSError errorWithDomain:@"AwemeCameraEnhancer" code:2 userInfo:nil]);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            [request addResourceWithType:PHAssetResourceTypePhoto fileURL:pairedImage options:nil];
            [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:pairedVideo options:nil];
        } completionHandler:^(BOOL success, NSError *error) {
            [[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
            ACEFinishLiveSave(success, error);
        }];
    };
    ((void (*)(id, SEL, NSURL *, NSURL *, NSURL *, id))objc_msgSend)(manager, selector, sourceImage, sourceVideo, directory, completion);
}

static id ACERepositoryFromOwner(id owner) {
    id repository = ACEValue(owner, @"repository");
    if (repository) return repository;
    id publishModel = ACEValue(owner, @"publishModel") ?: ACEValue(owner, @"viewModel");
    return ACEValue(publishModel, @"repository") ?: publishModel;
}

static void ACEWaitForNativeLiveSources(id owner, NSUInteger attempt) {
    id repository = ACERepositoryFromOwner(owner);
    id info = ACEValue(repository, @"repoLivePhotoInfoInstance");
    NSURL *imageURL = ACEFileURL(info, @[@"livePhotoImageSourceUrl"]);
    NSURL *videoURL = ACEFileURL(info, @[@"livePhotoVideoSourceUrl"]);
    if (imageURL && videoURL) {
        if (gACELiveSaveInProgress) return;
        gACELiveSaveInProgress = YES;
        gACEAwaitingNativeReturn = YES;
        gACELiveSaveFinished = NO;
        gACELiveSaveSucceeded = NO;
        ACELog(@"LIVE_PHOTO native sources ready attempt=%lu owner=%@ repository=%@ info=%@",
               (unsigned long)attempt, NSStringFromClass([owner class]), NSStringFromClass([repository class]), NSStringFromClass([info class]));
        ACEGenerateAndSaveLivePair(imageURL, videoURL);
        return;
    }
    if (attempt >= 30) {
        ACELog(@"LIVE_PHOTO editor source timeout owner=%@ repository=%@ info=%@ image=%@ video=%@",
               NSStringFromClass([owner class]), NSStringFromClass([repository class]), NSStringFromClass([info class]), imageURL, videoURL);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ACEWaitForNativeLiveSources(owner, attempt + 1);
    });
}

@interface ACEPreferencesController : UITableViewController @end
@implementation ACEPreferencesController
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"相机增强"; [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 5 : 8; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section == 0 ? @"拍摄设置" : @"首页文案"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"设置立即保存，重新进入拍摄页后完整生效。最长录制为24小时，仍受存储和系统限制。"
                        : @"请关闭 DYYY 的文案缩放、昵称缩放、昵称上下偏移和文案上下偏移。这里的正值表示向上移动。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray *titles = @[@"进入时默认视频", @"视频最长录制24小时", @"默认开启动态照片", @"动态照片自动保存并返回"];
    NSArray *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:path];
    cell.accessoryView = nil;
    cell.detailTextLabel.text = nil;
    if (path.section == 1) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (path.row == 0) {
            cell.textLabel.text = @"文案真实字号重排";
            UISwitch *toggle = [UISwitch new];
            toggle.on = ACEEnabled(kACEDescriptionReflowKey);
            [toggle addTarget:self action:@selector(descriptionReflowChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else if (path.row == 1) {
            cell.textLabel.text = [NSString stringWithFormat:@"文案字号比例：%.2f", ACEDescriptionScale()];
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = 0.3; stepper.maximumValue = 1.0; stepper.stepValue = 0.01;
            stepper.value = ACEDescriptionScale();
            [stepper addTarget:self action:@selector(descriptionScaleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else if (path.row == 2) {
            cell.textLabel.text = [NSString stringWithFormat:@"文案字重增强：%.1f", ACEDescriptionWeightBoost()];
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = 0.0; stepper.maximumValue = 1.0; stepper.stepValue = 0.1;
            stepper.value = ACEDescriptionWeightBoost();
            [stepper addTarget:self action:@selector(descriptionWeightChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else if (path.row == 3) {
            cell.textLabel.text = [NSString stringWithFormat:@"文案上移：%.0f px", ACEConfiguredVerticalOffset(kACEDescriptionOffsetKey)];
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = -100; stepper.maximumValue = 100; stepper.stepValue = 1;
            stepper.value = ACEConfiguredVerticalOffset(kACEDescriptionOffsetKey);
            [stepper addTarget:self action:@selector(descriptionOffsetChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else if (path.row == 4) {
            cell.textLabel.text = @"昵称真实字号缩放";
            UISwitch *toggle = [UISwitch new];
            toggle.on = ACEEnabled(kACENicknameReflowKey);
            [toggle addTarget:self action:@selector(nicknameReflowChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        } else if (path.row == 5) {
            cell.textLabel.text = [NSString stringWithFormat:@"昵称字号比例：%.2f", ACENicknameScale()];
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = 0.3; stepper.maximumValue = 1.5; stepper.stepValue = 0.01;
            stepper.value = ACENicknameScale();
            [stepper addTarget:self action:@selector(nicknameScaleChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else if (path.row == 6) {
            cell.textLabel.text = [NSString stringWithFormat:@"有文案时昵称上移：%.0f px", ACEConfiguredVerticalOffset(kACENicknameOffsetKey)];
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = -100; stepper.maximumValue = 100; stepper.stepValue = 1;
            stepper.value = ACEConfiguredVerticalOffset(kACENicknameOffsetKey);
            [stepper addTarget:self action:@selector(nicknameOffsetChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"无文案时昵称上移：%.0f px", ACEConfiguredVerticalOffset(kACENicknameNoDescriptionOffsetKey)];
            UIStepper *stepper = [UIStepper new];
            stepper.minimumValue = -100; stepper.maximumValue = 100; stepper.stepValue = 1;
            stepper.value = ACEConfiguredVerticalOffset(kACENicknameNoDescriptionOffsetKey);
            [stepper addTarget:self action:@selector(nicknameNoDescriptionOffsetChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = stepper;
        }
        return cell;
    }
    if (path.row == 4) {
        cell.textLabel.text = [NSString stringWithFormat:@"右侧按钮上移：%.0f px", ACERightButtonsOffset()];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIStepper *stepper = [UIStepper new];
        stepper.minimumValue = -100; stepper.maximumValue = 100; stepper.stepValue = 1;
        stepper.value = ACERightButtonsOffset();
        [stepper addTarget:self action:@selector(offsetChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stepper;
        return cell;
    }
    cell.textLabel.text = titles[path.row]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *toggle = [UISwitch new]; toggle.tag = path.row; toggle.on = ACEEnabled(keys[path.row]);
    [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell;
}
- (void)descriptionReflowChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:kACEDescriptionReflowKey];
}
- (void)descriptionScaleChanged:(UIStepper *)sender {
    CGFloat rounded = round(sender.value * 100.0) / 100.0;
    [NSUserDefaults.standardUserDefaults setDouble:rounded forKey:kACEDescriptionScaleKey];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)descriptionWeightChanged:(UIStepper *)sender {
    CGFloat rounded = round(sender.value * 10.0) / 10.0;
    [NSUserDefaults.standardUserDefaults setDouble:rounded forKey:kACEDescriptionWeightKey];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)descriptionOffsetChanged:(UIStepper *)sender {
    [NSUserDefaults.standardUserDefaults setDouble:sender.value forKey:kACEDescriptionOffsetKey];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:3 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)nicknameReflowChanged:(UISwitch *)sender {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:kACENicknameReflowKey];
}
- (void)nicknameScaleChanged:(UIStepper *)sender {
    CGFloat rounded = round(sender.value * 100.0) / 100.0;
    [NSUserDefaults.standardUserDefaults setDouble:rounded forKey:kACENicknameScaleKey];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:5 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)nicknameOffsetChanged:(UIStepper *)sender {
    [NSUserDefaults.standardUserDefaults setDouble:sender.value forKey:kACENicknameOffsetKey];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:6 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)nicknameNoDescriptionOffsetChanged:(UIStepper *)sender {
    [NSUserDefaults.standardUserDefaults setDouble:sender.value forKey:kACENicknameNoDescriptionOffsetKey];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:7 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)changed:(UISwitch *)sender {
    NSArray *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    if (sender.tag >= 0 && sender.tag < (NSInteger)keys.count) [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:keys[sender.tag]];
}
- (void)offsetChanged:(UIStepper *)sender {
    [NSUserDefaults.standardUserDefaults setDouble:sender.value forKey:kACERightButtonsOffsetKey];
    ACERefreshRightButtonsOffset();
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:4 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}
@end

@interface ACEPreferencesEntryTarget : NSObject
@property(nonatomic, weak) UIViewController *presenter;
+ (instancetype)shared; - (void)open;
@end
@implementation ACEPreferencesEntryTarget
+ (instancetype)shared { static id value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [self new]; }); return value; }
- (void)open {
    UIViewController *presenter = self.presenter ?: ACETopController(); ACEPreferencesController *settings = [ACEPreferencesController new];
    if (presenter.navigationController) [presenter.navigationController pushViewController:settings animated:YES];
    else [presenter presentViewController:[[UINavigationController alloc] initWithRootViewController:settings] animated:YES completion:nil];
}
@end

%hook AWERecordModeHelperImpl
- (BOOL)isDefaultToPhotoModeForFirstLanding {
    ACELog(@"MODE first original-query forceVideo=%d", ACEEnabled(kACEVideoDefaultKey));
    ACETraceCameraEntry(@"first-landing");
    if (ACEEnabled(kACEVideoDefaultKey)) return NO;
    return %orig;
}
- (BOOL)isDefaultToPhotoModeForEveryLanding {
    ACELog(@"MODE every original-query forceVideo=%d", ACEEnabled(kACEVideoDefaultKey));
    if (ACEEnabled(kACEVideoDefaultKey)) return NO;
    return %orig;
}
%end

%hook AWEPlayInteractionDescriptionElement
- (void)layoutElementView {
    %orig;
    if (!ACEEnabled(kACEDescriptionReflowKey)) return;
    __weak id weakElement = self;
    // Run after every participant in the hook chain (including DYYY) has
    // completed its layout pass, so a plugin load-order change cannot restore
    // the container-scale transform on the same pass.
    dispatch_async(dispatch_get_main_queue(), ^{
        ACEApplyDescriptionReflow(weakElement);
    });
}
%end

%hook AWEPlayInteractionAuthorElement
- (void)layoutElementView {
    %orig;
    if (!ACEEnabled(kACENicknameReflowKey)) return;
    __weak id weakElement = self;
    dispatch_async(dispatch_get_main_queue(), ^{ ACEApplyNicknameReflow(weakElement); });
}
%end

%hook AWEPlayInteractionStandardAuthorElement
- (void)layoutElementView {
    %orig;
    if (!ACEEnabled(kACENicknameReflowKey)) return;
    __weak id weakElement = self;
    dispatch_async(dispatch_get_main_queue(), ^{ ACEApplyNicknameReflow(weakElement); });
}
%end


%hook AWEPlayInteractionDanmakuElement
- (void)layoutElementView {
    %orig;
    if (!ACEEnabled(kACENicknameReflowKey)) return;
    __weak id weakElement = self;
    dispatch_async(dispatch_get_main_queue(), ^{ ACEApplyNicknameFollowerOffset(weakElement); });
}
%end

%hook AWEPlayInteractionRecommendToFeedCardLabelElement
- (void)layoutElementView {
    %orig;
    if (!ACEEnabled(kACENicknameReflowKey)) return;
    __weak id weakElement = self;
    // Keep the complete recommendation pill (visuals and hit-testing) aligned
    // with the nickname group. Applying this to the arranged element also
    // avoids accumulating offsets when feed cells are reused.
    dispatch_async(dispatch_get_main_queue(), ^{ ACEApplyNicknameFollowerOffset(weakElement); });
}
%end


%hook AWERecommendToFriendCardLabelView
- (void)layoutSubviews {
    %orig;
    ACEApplyNicknameFollowerViewOffset((UIView *)self);
}

- (void)didMoveToWindow {
    %orig;
    ACEApplyNicknameFollowerViewOffset((UIView *)self);
}
%end

%group ACEProfileCommentBarGroup
%hook ACECommentInputContainerView
- (void)layoutSubviews {
    %orig;
    ACEApplyDYYYProfileCommentBarHeight(self);
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    BOOL originallyInside = %orig;
    if (originallyInside) return YES;
    CGFloat compensation = ACEProfileCommentContentCompensation(self);
    if (compensation <= 0) return NO;
    CGRect interactiveBounds = ((UIView *)self).bounds;
    interactiveBounds.origin.y -= compensation;
    interactiveBounds.size.height += compensation;
    return CGRectContainsPoint(interactiveBounds, point);
}
%end
%end

%hook ACCRecordConfigServiceImpl
- (double)videoMaxDuration {
    double original = %orig;
    if (!ACEEnabled(kACEUnlimitedDurationKey)) return original;
    return MAX(original, kACEMaxRecordDuration);
}
%end

%hook UIView
- (void)setTransform:(CGAffineTransform)transform {
    NSString *kind = objc_getAssociatedObject(self, &kACETextElementKindKey);
    BOOL applying = [objc_getAssociatedObject(self, &kACEApplyingTextTransformKey) boolValue];
    if (kind.length && !applying) {
        BOOL nickname = [kind hasPrefix:@"nickname"];
        BOOL enabled = ACEEnabled(nickname ? kACENicknameReflowKey : kACEDescriptionReflowKey);
        if (enabled) {
            NSString *key = [kind isEqualToString:@"nicknameNoDescription"] ? kACENicknameNoDescriptionOffsetKey
                : (nickname ? kACENicknameOffsetKey : kACEDescriptionOffsetKey);
            // Typography is scaled through real fonts.  Discard any later
            // container scale and preserve only the configured screen-point Y.
            transform = CGAffineTransformMakeTranslation(0, ACEVerticalOffset(key));
        }
    }
    %orig(transform);
}
%end

%hook UIStackView
- (void)setTransform:(CGAffineTransform)transform {
    BOOL registered = [objc_getAssociatedObject(self, &kACERightStackRegisteredKey) boolValue];
    BOOL applying = [objc_getAssociatedObject(self, &kACEApplyingTransformKey) boolValue];
    if (registered && !applying) {
        // DYYY assigns a fresh scale transform on every reused feed cell. Add the
        // offset at the assignment boundary so video changes cannot erase it.
        transform.ty -= ACERightButtonsOffset();
    }
    %orig(transform);
}
- (void)layoutSubviews {
    %orig;
    UIViewController *controller = ACEViewControllerForView(self);
    Class interactionClass = NSClassFromString(@"AWEPlayInteractionViewController");
    if (!interactionClass || ![controller isKindOfClass:interactionClass]) return;

    BOOL isRightStack = [self.accessibilityLabel isEqualToString:@"right"];
    if (!isRightStack) {
        isRightStack = ACEViewContainsClass(self, NSClassFromString(@"AWEPlayInteractionUserAvatarView"));
    }
    if (!isRightStack) {
        SEL elementNameSelector = NSSelectorFromString(@"elementClassName");
        for (UIView *subview in [self.subviews copy]) {
            if (![subview respondsToSelector:elementNameSelector]) continue;
            NSString *elementName = ((id (*)(id, SEL))objc_msgSend)(subview, elementNameSelector);
            if ([elementName isEqualToString:@"AWEPlayInteractionUserAvatarOptElementElement"]) {
                isRightStack = YES;
                break;
            }
        }
    }
    if (isRightStack) {
        ACEApplyRightButtonsOffset(self);
    }
}
%end

%hook ACCRecordSystemLivePhotoServiceImpl
- (id)initWithPublishModel:(id)publishModel serviceProvider:(id)provider featureConfig:(id)featureConfig {
    id result = %orig;
    gACESystemLivePhotoService = result;
    ACELog(@"LIVE native record service initialized class=%@", NSStringFromClass([result class]));
    if (ACEEnabled(kACELivePhotoDefaultKey)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ACCRecordSystemLivePhotoServiceImpl *service = result;
            [service setEnableSystemLivePhoto:YES];
            [service toggleLivePhotoInnerSwitch:YES];
            ACELog(@"LIVE native inner switch enabled");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [service reopenSystemLivePhotoRecording];
                ACELog(@"LIVE native recording reopened");
            });
        });
    }
    return result;
}
- (void)takeLivePhotoPicture {
    gACESystemLivePhotoService = self;
    ACELog(@"LIVE native service take-picture");
    %orig;
}
%end

%hook ACCRecordFlowComponent
- (void)didSetMaxDuration:(double)duration {
    if (ACEEnabled(kACEUnlimitedDurationKey)) duration = MAX(duration, kACEMaxRecordDuration);
    %orig;
}
- (void)onCaptureStillImageWithImage:(id)image error:(NSError *)error {
    gACECameraController = ACETopController(); %orig;
    if (!ACEEnabled(kACEPhotoSaveKey) || error || ![image isKindOfClass:UIImage.class]) return;
    if (!ACEEnabled(kACELivePhotoDefaultKey)) {
        gACEAwaitingNativeReturn = YES;
        gACELiveSaveFinished = NO;
        gACELiveSaveSucceeded = NO;
        ACESaveStatic(image);
    }
}
- (void)flowServiceDidSystemLivePhotoWithPicture:(id)picture {
    ACELog(@"LIVE captured class=%@ value=%@", NSStringFromClass([picture class]), picture); %orig;
}
%end

%hook ACCVideoEditFlowControlComponent
- (void)componentDidAppear {
    %orig;
    gACEEditFlowControl = self;
    ACELog(@"LIVE edit flow appeared awaiting=%d saveFinished=%d", gACEAwaitingNativeReturn, gACELiveSaveFinished);
    if (ACEEnabled(kACEPhotoSaveKey) && ACEEnabled(kACELivePhotoDefaultKey) && !gACELiveSaveInProgress) {
        ACELog(@"LIVE_PHOTO probing editor publishModel=%@ repository=%@",
               NSStringFromClass([ACEValue(self, @"publishModel") class]), NSStringFromClass([ACERepositoryFromOwner(self) class]));
        ACEWaitForNativeLiveSources(self, 0);
    }
    ACETryNativeReturn();
}
%end

%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *original = %orig;
    BOOL isMainSettings = NO;
    for (AWESettingSectionModel *section in original) {
        if ([section.sectionHeaderTitle isEqualToString:@"账号"]) isMainSettings = YES;
        if ([section.sectionHeaderTitle isEqualToString:@"相机增强"]) return original;
        for (AWESettingItemModel *item in section.itemArray) {
            if ([item.identifier isEqualToString:@"com.swiftss.awemecameraenhancer.settings"]) return original;
        }
    }
    if (!isMainSettings) return original;

    AWESettingItemModel *item = [NSClassFromString(@"AWESettingItemModel") new];
    AWESettingSectionModel *section = [NSClassFromString(@"AWESettingSectionModel") new];
    if (!item || !section) return original;
    item.identifier = @"com.swiftss.awemecameraenhancer.settings";
    item.title = @"相机增强";
    item.detail = @"1.4.7";
    item.type = 0;
    item.svgIconImageName = @"ic_sapling_outlined";
    item.cellType = 26;
    item.colorStyle = 2;
    item.isEnable = YES;
    __weak AWESettingsViewModel *weakSelf = self;
    item.cellTappedBlock = ^{
        UIViewController *presenter = weakSelf.controllerDelegate ?: ACETopController();
        ACEPreferencesEntryTarget.shared.presenter = presenter;
        [ACEPreferencesEntryTarget.shared open];
    };
    section.itemArray = @[item];
    section.type = 0;
    section.sectionHeaderHeight = 40;
    section.sectionHeaderTitle = @"相机增强";
    NSMutableArray *result = [original mutableCopy] ?: [NSMutableArray array];
    [result insertObject:section atIndex:0];
    return result;
}
%end


%ctor {
    %init;
    Class commentInputClass = objc_getClass("AWECommentInputViewSwiftImpl.CommentInputContainerView");
    if (commentInputClass) %init(ACEProfileCommentBarGroup, ACECommentInputContainerView = commentInputClass);
}
