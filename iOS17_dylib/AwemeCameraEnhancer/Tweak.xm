#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/message.h>

@interface ACCRecordFlowComponent : NSObject
- (void)restoreRecordButtonState;
- (void)clearSystemLivePhotoData:(id)completion;
@end
@interface ACCSystemLivePhotoFlowComponent : NSObject
- (void)takeLivePhotoPicture;
@end
@interface ACCRealLivePhotoServiceImpl : NSObject
- (void)changeLivePhotoToMode:(unsigned long long)mode;
- (void)updateLivePhotoBarItem;
@end

static const NSTimeInterval kACEMaxRecordDuration = 86400.0;
static NSString *const kACELogName = @"AwemeCameraEnhancer.log";
static NSString *const kACEVideoDefaultKey = @"ACEVideoDefaultEnabled";
static NSString *const kACEUnlimitedDurationKey = @"ACEUnlimitedDurationEnabled";
static NSString *const kACELivePhotoDefaultKey = @"ACELivePhotoDefaultEnabled";
static NSString *const kACEPhotoSaveKey = @"ACEPhotoAutoSaveEnabled";
static __weak UIViewController *gACECameraController;
static NSUInteger gACECameraEntryCount = 0;
static __weak ACCRealLivePhotoServiceImpl *gACELivePhotoService;
static __weak id gACESystemLivePhotoService;
static NSUInteger gACEStillCaptureGeneration = 0;
static NSUInteger gACELiveCallbackGeneration = 0;

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
            if (ACEEnabled(kACELivePhotoDefaultKey) && gACELivePhotoService &&
                ([NSStringFromClass(top.class) isEqualToString:@"AWERecorderViewController"])) {
                [gACELivePhotoService changeLivePhotoToMode:1];
                [gACELivePhotoService updateLivePhotoBarItem];
                ACELog(@"LIVE native mode and bar refreshed after=%.2f", delay.doubleValue);
            }
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

static void ACEReturnToCamera(ACCRecordFlowComponent *flow, BOOL saved) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if ([flow respondsToSelector:@selector(clearSystemLivePhotoData:)]) [flow clearSystemLivePhotoData:^{}];
        if ([flow respondsToSelector:@selector(restoreRecordButtonState)]) [flow restoreRecordButtonState];
        UIViewController *camera = gACECameraController, *top = ACETopController();
        if (camera && top != camera) {
            UINavigationController *navigation = top.navigationController;
            if (navigation && [navigation.viewControllers containsObject:camera]) [navigation popToViewController:camera animated:YES];
            else if (top.presentingViewController) [top dismissViewControllerAnimated:YES completion:nil];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ACEShowToast(camera ?: ACETopController(), saved ? @"照片已保存到相册" : @"照片保存失败");
        });
        ACELog(@"PHOTO returned-to-camera saved=%d", saved);
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

static void ACESaveStatic(UIImage *image, ACCRecordFlowComponent *flow) {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{ [PHAssetChangeRequest creationRequestForAssetFromImage:image]; }
                                      completionHandler:^(BOOL success, NSError *error) {
        ACELog(@"PHOTO static saved=%d error=%@", success, error); ACEReturnToCamera(flow, success);
    }];
}

static BOOL ACESaveLive(id picture, ACCRecordFlowComponent *flow) {
    NSArray *imageKeys = @[@"livePhotoImageFileURL", @"livePhotoImageURL", @"livePhotoImagePath", @"imageFileURL", @"imageURL", @"imagePath"];
    NSArray *videoKeys = @[@"livePhotoVideoFileURL", @"livePhotoVideoURL", @"livePhotoVideoPath", @"livePhotoVideoFilePath", @"systemLivePhotoVideoFramePath", @"videoURL", @"videoPath"];
    NSURL *imageURL = ACEFileURL(picture, imageKeys) ?: ACEFileURL(flow, imageKeys);
    NSURL *videoURL = ACEFileURL(picture, videoKeys) ?: ACEFileURL(flow, videoKeys);
    UIImage *image = [picture isKindOfClass:UIImage.class] ? picture : ACEValue(picture, @"image");
    NSData *imageData = imageURL ? [NSData dataWithContentsOfURL:imageURL] : ([image isKindOfClass:UIImage.class] ? UIImageJPEGRepresentation(image, 0.98) : nil);
    if (!imageData || !videoURL) {
        ACELog(@"LIVE_PHOTO resources missing picture=%@ image=%@ video=%@", NSStringFromClass([picture class]), imageURL, videoURL);
        return NO;
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        [request addResourceWithType:PHAssetResourceTypePhoto data:imageData options:nil];
        [request addResourceWithType:PHAssetResourceTypePairedVideo fileURL:videoURL options:nil];
    } completionHandler:^(BOOL success, NSError *error) {
        ACELog(@"LIVE_PHOTO paired saved=%d error=%@", success, error); ACEReturnToCamera(flow, success);
    }];
    return YES;
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

%hook ACCRealLivePhotoServiceImpl
- (id)init {
    id result = %orig;
    gACELivePhotoService = result;
    ACELog(@"LIVE service initialized class=%@", NSStringFromClass([result class]));
    if (ACEEnabled(kACELivePhotoDefaultKey)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ACCRealLivePhotoServiceImpl *service = result;
            [service changeLivePhotoToMode:1];
            [service updateLivePhotoBarItem];
            ACELog(@"LIVE service-init mode and bar refreshed immediately");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [service changeLivePhotoToMode:1];
                [service updateLivePhotoBarItem];
                ACELog(@"LIVE service-init mode and bar refreshed delayed");
            });
        });
    }
    return result;
}
- (void)changeLivePhotoToMode:(unsigned long long)mode {
    if (ACEEnabled(kACELivePhotoDefaultKey)) mode = 1;
    ACELog(@"LIVE selected mode=%llu", mode);
    %orig;
}
- (void)changeLivePhotoToMode:(unsigned long long)mode updateBlock:(id)block {
    if (ACEEnabled(kACELivePhotoDefaultKey)) mode = 1;
    ACELog(@"LIVE selected mode-block=%llu", mode);
    %orig;
}
%end

%hook ACCRecordSystemLivePhotoServiceImpl
- (BOOL)systemLivePhotoOpened {
    gACESystemLivePhotoService = self;
    BOOL original = %orig;
    BOOL enabled = ACEEnabled(kACELivePhotoDefaultKey) ? YES : original;
    ACELog(@"LIVE system-opened original=%d result=%d", original, enabled);
    return enabled;
}
- (void)takeLivePhotoPicture {
    gACESystemLivePhotoService = self;
    ACELog(@"LIVE native service take-picture");
    %orig;
}
%end

%hook ACCPictureFlowComponent
- (void)tryTakePicture {
    if (ACEEnabled(kACELivePhotoDefaultKey)) {
        id service = ACEValue(self, @"systemLivePhotoService") ?: gACESystemLivePhotoService;
        SEL selector = NSSelectorFromString(@"takeLivePhotoPicture");
        if ([service respondsToSelector:selector]) {
            ACELog(@"LIVE redirect picture flow service=%@", NSStringFromClass([service class]));
            ((void (*)(id, SEL))objc_msgSend)(service, selector);
            return;
        }
        ACELog(@"LIVE redirect unavailable system-service=%@", NSStringFromClass([service class]));
    }
    %orig;
}
%end

%hook ACCSystemLivePhotoFlowComponent
- (void)tryTakePicture {
    if (ACEEnabled(kACELivePhotoDefaultKey)) {
        ACELog(@"LIVE force native capture");
        [self takeLivePhotoPicture];
        return;
    }
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
        ACESaveStatic(image, self);
        return;
    }
    NSUInteger token = ++gACEStillCaptureGeneration;
    NSUInteger liveGeneration = gACELiveCallbackGeneration;
    UIImage *fallbackImage = image;
    ACELog(@"LIVE still callback waiting paired token=%lu", (unsigned long)token);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token == gACEStillCaptureGeneration && liveGeneration == gACELiveCallbackGeneration) {
            ACELog(@"LIVE paired callback timeout; save static fallback token=%lu", (unsigned long)token);
            ACESaveStatic(fallbackImage, self);
        }
    });
}
- (void)flowServiceDidSystemLivePhotoWithPicture:(id)picture {
    gACELiveCallbackGeneration++;
    ACELog(@"LIVE captured class=%@ value=%@", NSStringFromClass([picture class]), picture); %orig;
    if (ACEEnabled(kACEPhotoSaveKey) && !ACESaveLive(picture, self)) ACELog(@"LIVE paired asset unavailable; static fallback intentionally skipped");
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


%ctor { @autoreleasepool { if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.ss.iphone.ugc.Aweme"]) ACELog(@"START version=1.2.5 service-init Live Photo"); } }
