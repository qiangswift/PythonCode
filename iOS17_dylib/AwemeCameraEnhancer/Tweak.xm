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

static const NSTimeInterval kACEMaxRecordDuration = 86400.0;
static NSString *const kACEVideoDefaultKey = @"ACEVideoDefaultEnabled";
static NSString *const kACEUnlimitedDurationKey = @"ACEUnlimitedDurationEnabled";
static NSString *const kACELivePhotoDefaultKey = @"ACELivePhotoDefaultEnabled";
static NSString *const kACEPhotoSaveKey = @"ACEPhotoAutoSaveEnabled";
static NSString *const kACERightButtonsOffsetKey = @"ACERightButtonsVerticalOffset";
static __weak UIViewController *gACECameraController;
static __weak ACCRecordSystemLivePhotoServiceImpl *gACESystemLivePhotoService;
static __weak ACCVideoEditFlowControlComponent *gACEEditFlowControl;
static BOOL gACEAwaitingNativeReturn = NO;
static BOOL gACELiveSaveFinished = NO;
static BOOL gACELiveSaveSucceeded = NO;
static BOOL gACELiveSaveInProgress = NO;
static char kACERightStackRegisteredKey;
static char kACEApplyingTransformKey;

static BOOL ACEEnabled(NSString *key) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:key] == nil ? YES : [defaults boolForKey:key];
}

#define ACELog(...) do { } while (0)

static CGFloat ACERightButtonsOffset(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:kACERightButtonsOffsetKey] == nil ? 8.0 : [defaults doubleForKey:kACERightButtonsOffsetKey];
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
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 5; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"拍摄设置"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"设置立即保存，重新进入拍摄页后完整生效。最长录制为24小时，仍受存储和系统限制。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray *titles = @[@"进入时默认视频", @"视频最长录制24小时", @"默认开启动态照片", @"动态照片自动保存并返回"];
    NSArray *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:path];
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

%hook ACCRecordConfigServiceImpl
- (double)videoMaxDuration {
    double original = %orig;
    if (!ACEEnabled(kACEUnlimitedDurationKey)) return original;
    return MAX(original, kACEMaxRecordDuration);
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
    item.detail = @"1.3.4";
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


%ctor { }
