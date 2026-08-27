#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>

@interface ACCRecordSystemLivePhotoServiceImpl : NSObject
- (void)setEnableSystemLivePhoto:(BOOL)enabled;
- (void)toggleLivePhotoInnerSwitch:(BOOL)enabled;
- (void)reopenSystemLivePhotoRecording;
@end
@interface ACCVideoEditFlowControlComponent : NSObject
- (BOOL)backToShootNeedAlert:(BOOL)needAlert;
@end

static const NSTimeInterval kACEMaxRecordDuration = 86400.0;
static NSString *const kACELogName = @"AwemeCameraEnhancer.log";
static NSString *const kACEVideoDefaultKey = @"ACEVideoDefaultEnabled";
static NSString *const kACEUnlimitedDurationKey = @"ACEUnlimitedDurationEnabled";
static NSString *const kACELivePhotoDefaultKey = @"ACELivePhotoDefaultEnabled";
static NSString *const kACEPhotoSaveKey = @"ACEPhotoAutoSaveEnabled";
static __weak UIViewController *gACECameraController;
static NSUInteger gACECameraEntryCount = 0;
static __weak ACCRecordSystemLivePhotoServiceImpl *gACESystemLivePhotoService;
static __weak ACCVideoEditFlowControlComponent *gACEEditFlowControl;
static BOOL gACEAwaitingNativeReturn = NO;
static BOOL gACELiveSaveFinished = NO;
static BOOL gACELiveSaveSucceeded = NO;
static BOOL gACELiveSaveInProgress = NO;

static BOOL ACEEnabled(NSString *key) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:key] == nil ? YES : [defaults boolForKey:key];
}

static void ACELog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [documents stringByAppendingPathComponent:kACELogName];
    NSData *data = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message] dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) { [data writeToFile:path atomically:YES]; return; }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile]; [handle writeData:data]; [handle closeFile];
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
    NSUInteger entry = ++gACECameraEntryCount;
    ACELog(@"ENTRY #%lu source=%@ top-now=%@", (unsigned long)entry, source, NSStringFromClass(ACETopController().class));
    for (NSNumber *delay in @[@0.25, @0.75, @1.5, @3.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *top = ACETopController();
            ACELog(@"ENTRY #%lu after=%.2f top=%@ presented=%d", (unsigned long)entry, delay.doubleValue,
                   NSStringFromClass(top.class), top.presentingViewController != nil);
        });
    }
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
        BOOL handled = [flow backToShootNeedAlert:NO];
        gACELiveSaveInProgress = NO;
        ACELog(@"LIVE native back-to-shoot handled=%d saved=%d", handled, saved);
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
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 4; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"拍摄设置"; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return @"设置立即保存，重新进入拍摄页后完整生效。最长录制为24小时，仍受存储和系统限制。"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray *titles = @[@"进入时默认视频", @"视频最长录制24小时", @"默认开启动态照片", @"动态照片自动保存并返回"];
    NSArray *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:path];
    cell.textLabel.text = titles[path.row]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *toggle = [UISwitch new]; toggle.tag = path.row; toggle.on = ACEEnabled(keys[path.row]);
    [toggle addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle; return cell;
}
- (void)changed:(UISwitch *)sender {
    NSArray *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    if (sender.tag >= 0 && sender.tag < (NSInteger)keys.count) [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:keys[sender.tag]];
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

static void ACEInstallSettingsEntry(UIViewController *controller) {
    NSMutableArray *items = [NSMutableArray arrayWithArray:controller.navigationItem.rightBarButtonItems ?: @[]];
    for (UIBarButtonItem *item in items) if ([item.title isEqualToString:@"相机增强"]) return;
    ACEPreferencesEntryTarget.shared.presenter = controller;
    [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"相机增强" style:UIBarButtonItemStylePlain target:ACEPreferencesEntryTarget.shared action:@selector(open)]];
    controller.navigationItem.rightBarButtonItems = items; ACELog(@"SETTINGS installed class=%@", NSStringFromClass(controller.class));

    const NSInteger buttonTag = 0xACE1201;
    if (![controller.view viewWithTag:buttonTag]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = buttonTag;
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.92];
        button.layer.cornerRadius = 20;
        [button setTitle:@"相机增强" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        [button addTarget:ACEPreferencesEntryTarget.shared action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        [controller.view addSubview:button];
        [NSLayoutConstraint activateConstraints:@[
            [button.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
            [button.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor constant:-20],
            [button.widthAnchor constraintEqualToConstant:112], [button.heightAnchor constraintEqualToConstant:40]
        ]];
        ACELog(@"SETTINGS visible button installed");
    }
}

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

%hook AWEGeneralSettingViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ACEInstallSettingsEntry((UIViewController *)self);
}
%end
%hook AWESettingsTableViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ACEInstallSettingsEntry((UIViewController *)self);
}
%end
%hook AWESettingPageBaseController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ACEInstallSettingsEntry((UIViewController *)self);
}
%end
%hook AWESettingBaseViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ACEInstallSettingsEntry((UIViewController *)self);
}
%end
%hook _TtC7FlowKit24AppSettingViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    ACEInstallSettingsEntry((UIViewController *)self);
}
%end


%ctor { @autoreleasepool { if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.ss.iphone.ugc.Aweme"]) ACELog(@"START version=1.2.7 editor Live Photo pipeline"); } }
