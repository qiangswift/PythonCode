#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <substrate.h>

@interface ACCRecordFlowComponent : NSObject
- (void)restoreRecordButtonState;
@end

static const NSTimeInterval kACEMaxRecordDuration = 86400.0; // practical unlimited: 24 hours
static NSString *const kACELogName = @"AwemeCameraEnhancer.log";
static NSString *const kACEVideoDefaultKey = @"ACEVideoDefaultEnabled";
static NSString *const kACEUnlimitedDurationKey = @"ACEUnlimitedDurationEnabled";
static NSString *const kACELivePhotoDefaultKey = @"ACELivePhotoDefaultEnabled";
static NSString *const kACEPhotoSaveKey = @"ACEPhotoAutoSaveEnabled";
static void ACELog(NSString *format, ...);

static BOOL ACEPreferenceEnabled(NSString *key) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults objectForKey:key] == nil ? YES : [defaults boolForKey:key];
}

@interface ACEPreferencesController : UITableViewController
@end

@implementation ACEPreferencesController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"相机增强";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"ACESwitchCell"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @"拍摄设置";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"设置立即保存；重新进入拍摄页后完整生效。录像“不限时”设为 24 小时，仍受设备存储和系统限制。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSString *> *titles = @[@"进入时默认视频", @"视频拍摄不限时", @"默认开启动态照片", @"照片自动保存并恢复拍摄态"];
    NSArray<NSString *> *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ACESwitchCell" forIndexPath:indexPath];
    cell.textLabel.text = titles[indexPath.row];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.tag = indexPath.row;
    toggle.on = ACEPreferenceEnabled(keys[indexPath.row]);
    [toggle addTarget:self action:@selector(ace_switchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)ace_switchChanged:(UISwitch *)sender {
    NSArray<NSString *> *keys = @[kACEVideoDefaultKey, kACEUnlimitedDurationKey, kACELivePhotoDefaultKey, kACEPhotoSaveKey];
    if (sender.tag < 0 || sender.tag >= (NSInteger)keys.count) return;
    NSString *key = keys[sender.tag];
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:key];
    ACELog(@"PREFERENCE %@=%d", key, sender.isOn);
}

@end

static void ACELog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [documents stringByAppendingPathComponent:kACELogName];
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
        return;
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle closeFile];
}

%hook AWERecordModeHelperImpl

- (BOOL)isDefaultToPhotoModeForFirstLanding {
    if (!ACEPreferenceEnabled(kACEVideoDefaultKey)) return %orig;
    ACELog(@"MODE first-landing photo -> video");
    return NO;
}

- (BOOL)isDefaultToPhotoModeForEveryLanding {
    if (!ACEPreferenceEnabled(kACEVideoDefaultKey)) return %orig;
    ACELog(@"MODE every-landing photo -> video");
    return NO;
}

%end

%hook ACCRecordConfigServiceImpl

- (double)videoMaxDuration {
    double original = %orig;
    if (!ACEPreferenceEnabled(kACEUnlimitedDurationKey)) return original;
    ACELog(@"DURATION %.3f -> %.0f", original, kACEMaxRecordDuration);
    return MAX(original, kACEMaxRecordDuration);
}

%end

%hook ACCRecordFlowComponent

- (void)didSetMaxDuration:(double)duration {
    if (!ACEPreferenceEnabled(kACEUnlimitedDurationKey)) {
        %orig(duration);
        return;
    }
    double adjusted = MAX(duration, kACEMaxRecordDuration);
    ACELog(@"MAX_SET %.3f -> %.0f", duration, adjusted);
    %orig(adjusted);
}

- (void)onCaptureStillImageWithImage:(id)image error:(NSError *)error {
    %orig;
    if (!ACEPreferenceEnabled(kACEPhotoSaveKey)) return;
    if (error || ![image isKindOfClass:[UIImage class]]) {
        ACELog(@"PHOTO skip-save error=%@ class=%@", error, [image class]);
        return;
    }

    UIImage *capturedImage = (UIImage *)image;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:capturedImage];
    } completionHandler:^(BOOL success, NSError *saveError) {
        ACELog(@"PHOTO saved=%d error=%@", success, saveError);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self respondsToSelector:@selector(restoreRecordButtonState)]) {
                [self restoreRecordButtonState];
                ACELog(@"PHOTO record button restored");
            }
        });
    }];
}

- (void)flowServiceDidSystemLivePhotoWithPicture:(id)picture {
    ACELog(@"LIVE_PHOTO captured class=%@ value=%@", NSStringFromClass([picture class]), picture);
    %orig;
}

%end

// This is Douyin's own experiment gate for automatically enabling the native
// Live Photo capture flow on first entry. Hook only the exact selector and let
// the app perform all camera/session setup itself.
static BOOL (*ACEOriginalLivePhotoAutoOpen)(id, SEL);
static BOOL gACELivePhotoGateInstalled = NO;
static BOOL ACEForceLivePhotoAutoOpen(id self, SEL _cmd) {
    if (!ACEPreferenceEnabled(kACELivePhotoDefaultKey)) {
        return ACEOriginalLivePhotoAutoOpen ? ACEOriginalLivePhotoAutoOpen(self, _cmd) : NO;
    }
    ACELog(@"LIVE_PHOTO native first-entry auto-open -> YES class=%@", NSStringFromClass([self class]));
    return YES;
}

%hook AWEGeneralSettingViewController

- (void)viewDidLoad {
    %orig;
    UIViewController *settingsController = (UIViewController *)self;
    UIBarButtonItem *entry = [[UIBarButtonItem alloc] initWithTitle:@"相机增强"
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(ace_openCameraEnhancerSettings)];
    NSMutableArray *items = [NSMutableArray arrayWithArray:settingsController.navigationItem.rightBarButtonItems ?: @[]];
    BOOL exists = NO;
    for (UIBarButtonItem *item in items) {
        if ([item.title isEqualToString:@"相机增强"]) { exists = YES; break; }
    }
    if (!exists) {
        [items addObject:entry];
        settingsController.navigationItem.rightBarButtonItems = items;
    }
    ACELog(@"SETTINGS entry installed");
}

%new
- (void)ace_openCameraEnhancerSettings {
    ACEPreferencesController *controller = [[ACEPreferencesController alloc] init];
    UIViewController *settingsController = (UIViewController *)self;
    [settingsController.navigationController pushViewController:controller animated:YES];
    ACELog(@"SETTINGS opened");
}

%end

static void ACEInstallLivePhotoGate(void) {
    if (gACELivePhotoGateInstalled) return;
    SEL selector = NSSelectorFromString(@"syncGetAWEToolRecordLivePhotoFirstEnterAutoOpen");
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;

    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    count = objc_getClassList(classes, count);
    BOOL installed = NO;
    for (int index = 0; index < count; index++) {
        Class cls = classes[index];
        Method instanceMethod = class_getInstanceMethod(cls, selector);
        if (instanceMethod && class_respondsToSelector(cls, selector)) {
            MSHookMessageEx(cls, selector, (IMP)ACEForceLivePhotoAutoOpen, (IMP *)&ACEOriginalLivePhotoAutoOpen);
            ACELog(@"LIVE_PHOTO hooked instance class=%@", NSStringFromClass(cls));
            gACELivePhotoGateInstalled = YES;
            installed = YES;
            break;
        }
        Class meta = object_getClass(cls);
        Method classMethod = class_getClassMethod(cls, selector);
        if (classMethod && class_respondsToSelector(meta, selector)) {
            MSHookMessageEx(meta, selector, (IMP)ACEForceLivePhotoAutoOpen, (IMP *)&ACEOriginalLivePhotoAutoOpen);
            ACELog(@"LIVE_PHOTO hooked class=%@", NSStringFromClass(cls));
            gACELivePhotoGateInstalled = YES;
            installed = YES;
            break;
        }
    }
    free(classes);
    if (!installed) ACELog(@"LIVE_PHOTO selector not loaded yet");
}

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"com.ss.iphone.ugc.Aweme"]) return;
        ACELog(@"START version=1.1.0 bundle=%@", bundle);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ACEInstallLivePhotoGate(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ACEInstallLivePhotoGate(); });
    }
}
