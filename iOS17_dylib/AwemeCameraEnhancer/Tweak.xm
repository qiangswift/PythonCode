#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@interface ACCRecordFlowComponent : NSObject
- (void)restoreRecordButtonState;
- (void)clearSystemLivePhotoData:(id)completion;
@end
@interface ACCSystemLivePhotoFlowComponent : NSObject
- (void)takeLivePhotoPicture;
@end

static const NSTimeInterval kACEMaxRecordDuration = 86400.0;
static NSString *const kACELogName = @"AwemeCameraEnhancer.log";
static NSString *const kACEVideoDefaultKey = @"ACEVideoDefaultEnabled";
static NSString *const kACEUnlimitedDurationKey = @"ACEUnlimitedDurationEnabled";
static NSString *const kACELivePhotoDefaultKey = @"ACELivePhotoDefaultEnabled";
static NSString *const kACEPhotoSaveKey = @"ACEPhotoAutoSaveEnabled";
static __weak UIViewController *gACECameraController;

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
}

%hook AWERecordModeHelperImpl
- (BOOL)isDefaultToPhotoModeForFirstLanding {
    if (ACEEnabled(kACEVideoDefaultKey)) return NO;
    return %orig;
}
- (BOOL)isDefaultToPhotoModeForEveryLanding {
    if (ACEEnabled(kACEVideoDefaultKey)) return NO;
    return %orig;
}
%end

%hook ACCRecordConfigServiceImpl
- (double)videoMaxDuration { double original = %orig; return ACEEnabled(kACEUnlimitedDurationKey) ? MAX(original, kACEMaxRecordDuration) : original; }
%end

%hook ACCRealLivePhotoServiceImpl
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
    if (ACEEnabled(kACEPhotoSaveKey) && !ACEEnabled(kACELivePhotoDefaultKey) && !error && [image isKindOfClass:UIImage.class]) ACESaveStatic(image, self);
}
- (void)flowServiceDidSystemLivePhotoWithPicture:(id)picture {
    ACELog(@"LIVE captured class=%@ value=%@", NSStringFromClass([picture class]), picture); %orig;
    if (ACEEnabled(kACEPhotoSaveKey) && !ACESaveLive(picture, self)) ACELog(@"LIVE paired asset unavailable; static fallback intentionally skipped");
}
%end

%hook AWEGeneralSettingViewController
- (void)viewDidAppear:(BOOL)animated { %orig; ACEInstallSettingsEntry((UIViewController *)self); }
%end
%hook AWESettingsTableViewController
- (void)viewDidAppear:(BOOL)animated { %orig; ACEInstallSettingsEntry((UIViewController *)self); }
%end
%hook AWESettingPageBaseController
- (void)viewDidAppear:(BOOL)animated { %orig; ACEInstallSettingsEntry((UIViewController *)self); }
%end
%hook AWESettingBaseViewController
- (void)viewDidAppear:(BOOL)animated { %orig; ACEInstallSettingsEntry((UIViewController *)self); }
%end
%hook _TtC7FlowKit24AppSettingViewController
- (void)viewDidAppear:(BOOL)animated { %orig; ACEInstallSettingsEntry((UIViewController *)self); }
%end

%ctor { @autoreleasepool { if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.ss.iphone.ugc.Aweme"]) ACELog(@"START version=1.2.0"); } }
