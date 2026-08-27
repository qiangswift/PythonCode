#import <HBLog.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <objc/runtime.h>
#import <notify.h>
#import <stdlib.h>

#import "Common.h"
#import "UIColor+.h"

#define IsNetworkTypeText(text) ( \
    [text isEqualToString:@"G"] || [text isEqualToString:@"3G"] || \
    [text isEqualToString:@"4G"] || [text containsString:@"5G"] || \
    [text isEqualToString:@"LTE"])

#define Is5GPlusNetworkTypeText(text) [text isEqualToString:@"5G+"]
#define Is5GAdvancedNetworkTypeText(text) (Is5GPlusNetworkTypeText(text) || [text isEqualToString:@"5GA"])

@interface STStatusBarDataEntry : NSObject
@property (getter=isEnabled, nonatomic, readonly) bool enabled;
@end

@interface STStatusBarDataCellularEntry : NSObject
@end

@interface STStatusBarDataWifiEntry : NSObject
@end

@interface STStatusBarData : NSObject
@property (nonatomic, readonly) STStatusBarDataCellularEntry *cellularEntry;
@property (nonatomic, readonly) STStatusBarDataCellularEntry *secondaryCellularEntry;
@property (nonatomic, readonly) STStatusBarDataEntry *vpnEntry;
@property (nonatomic, readonly) STStatusBarDataWifiEntry *wifiEntry;
- (STStatusBarData *)dataByReplacingEntry:(id)arg1 forKey:(NSString *)arg2;
@end

@interface STUIStatusBar : UIView
- (STStatusBarData *)currentAggregatedData;
- (STStatusBarData *)currentData;
@end

@interface STUIStatusBarStyleAttributes : NSObject
@property (nonatomic, copy) UIColor *textColor;
@property (nonatomic, copy) UIColor *imageDimmedTintColor;
@property (nonatomic, copy) UIColor *imageTintColor;
@property (nonatomic, copy) UIFont *font;
@end

@interface STUIStatusBarStringView : UILabel
- (void)svpnSet5GAdvancedText;
- (void)svpnApply5GAdvancedAttributesIfNeeded;
@end

@interface STUIStatusBarCellularNetworkTypeView : UIView
@property (nonatomic, strong) STUIStatusBarStringView *stringView;
@property (nonatomic, strong) NSLayoutConstraint *widthConstraint;
@end

@interface STUIStatusBarWifiSignalView : UIView
@property (nonatomic, strong) UIColor *inactiveColor;
@property (nonatomic, strong) UIColor *activeColor;
@end

@interface PSUIPrefsRootController : UITableViewController
@end

@interface SBDeviceApplicationSceneStatusBarBreadcrumbProvider : NSObject
- (id)breadcrumbActionsForActivatingSceneEntity:(id)entity withTransitionContext:(id)context;
@end

@interface UIStatusBarBreadcrumbItemView : UIView
@end

@interface UIStatusBarSystemNavigationItemView : UIView
@end

static BOOL _isEnabled = NO;
static BOOL _isVPNEnabled = NO;
static BOOL _isEnabledReversed = NO;
static BOOL _isForce5GAEnabled = NO;
static CGFloat _breadcrumbVerticalOffset = 0.0;

static UIColor *_darkReplacementColor = nil;
static UIColor *_lightReplacementColor = nil;
static dispatch_source_t _trafficTimer = nil;
static dispatch_source_t _settingsOverlayTimer = nil;
static BOOL _settingsRootVisible = NO;
static NSHashTable<UIView *> *_breadcrumbViews = nil;

static NSString *const SVPNTrafficBaselinesKey = @"TrafficBaselines";
static NSString *const SVPNCellularDownloadKey = @"TrafficCellularDownload";
static NSString *const SVPNCellularUploadKey = @"TrafficCellularUpload";
static NSString *const SVPNWifiDownloadKey = @"TrafficWifiDownload";
static NSString *const SVPNWifiUploadKey = @"TrafficWifiUpload";
static const char *SVPNBreadcrumbStateName = "com.82flex.singlevpnprefs.breadcrumb-state";
static const uint64_t SVPNBreadcrumbStateMagic = 0x5356ULL;
static int _breadcrumbStateToken = -1;

static BOOL svpnIsPreferenceAuthorityProcess(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    return [bundleIdentifier isEqualToString:@"com.apple.springboard"] || [bundleIdentifier isEqualToString:@"com.apple.Preferences"];
}

static void svpnPublishBreadcrumbState(void) {
    if (_breadcrumbStateToken < 0 && notify_register_check(SVPNBreadcrumbStateName, &_breadcrumbStateToken) != NOTIFY_STATUS_OK) return;
    int32_t milliOffset = (int32_t)llround(_breadcrumbVerticalOffset * 1000.0);
    uint64_t state = (SVPNBreadcrumbStateMagic << 48) | ((uint64_t)(_isEnabled ? 1 : 0) << 47) | (uint32_t)milliOffset;
    notify_set_state(_breadcrumbStateToken, state);
    notify_post("com.82flex.singlevpnprefs/breadcrumb-state-updated");
}

static BOOL svpnConsumeBreadcrumbState(void) {
    if (_breadcrumbStateToken < 0 && notify_register_check(SVPNBreadcrumbStateName, &_breadcrumbStateToken) != NOTIFY_STATUS_OK) return NO;
    uint64_t state = 0;
    if (notify_get_state(_breadcrumbStateToken, &state) != NOTIFY_STATUS_OK || (state >> 48) != SVPNBreadcrumbStateMagic) return NO;
    _isEnabled = ((state >> 47) & 1) != 0;
    _breadcrumbVerticalOffset = (CGFloat)(int32_t)(uint32_t)state / 1000.0;
    return YES;
}
static NSString *svpnBreadcrumbLogPath(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if ([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        return @"/var/mobile/Library/Preferences/com.82flex.singlevpn.breadcrumb.log";
    }
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return documents.length ? [documents stringByAppendingPathComponent:@"SingleVPNBreadcrumb.log"] : nil;
}

static void svpnBreadcrumbLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, message ?: @""];
    NSString *logPath = svpnBreadcrumbLogPath();
    if (!logPath.length) return;
    @synchronized (NSFileManager.defaultManager) {
        if (![NSFileManager.defaultManager fileExistsAtPath:logPath]) {
            NSError *error = nil;
            [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error) NSLog(@"[SingleVPN] breadcrumb log create failed: %@", error);
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    }
}

static NSString *svpnShortDescription(id object) {
    if (!object) return @"";
    NSString *description = nil;
    @try { description = [object description]; } @catch (__unused NSException *exception) { return @"<description-exception>"; }
    description = [description stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return description.length > 500 ? [[description substringToIndex:500] stringByAppendingString:@"..."] : description;
}

static void svpnLogObjectIvars(id object) {
    if (!object) return;
    for (Class cls = object_getClass(object); cls && cls != UIView.class; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int index = 0; index < count; index++) {
            Ivar ivar = ivars[index];
            const char *type = ivar_getTypeEncoding(ivar);
            if (!type || type[0] != '@') continue;
            id value = nil;
            @try { value = object_getIvar(object, ivar); } @catch (__unused NSException *exception) { value = nil; }
            if (value) {
                svpnBreadcrumbLog(@"live ivar owner=%@ name=%s valueClass=%@ value=%@", NSStringFromClass([object class]), ivar_getName(ivar), NSStringFromClass([value class]), svpnShortDescription(value));
            }
        }
        free(ivars);
    }
}

static void svpnLogTopStatusViews(UIView *view, UIWindow *window, NSUInteger depth) {
    if (!view || depth > 12) return;
    CGRect frame = [view convertRect:view.bounds toView:window];
    BOOL nearTop = CGRectGetMinY(frame) < 100.0 && CGRectGetMaxY(frame) > -20.0;
    if (nearTop && !view.hidden && view.alpha > 0.01) {
        NSString *className = NSStringFromClass(view.class);
        NSString *text = [view isKindOfClass:UILabel.class] ? ((UILabel *)view).text : nil;
        NSString *identifier = view.accessibilityIdentifier;
        if ([className.lowercaseString containsString:@"status"] || text.length || identifier.length) {
            svpnBreadcrumbLog(@"view depth=%lu class=%@ frame=%@ text=%@ identifier=%@", (unsigned long)depth, className, NSStringFromCGRect(frame), text ?: @"", identifier ?: @"");
            if ([className hasPrefix:@"STUIStatusBar"] || [className containsString:@"Navigation"] || [className containsString:@"Breadcrumb"]) {
                svpnLogObjectIvars(view);
            }
        }
    }
    for (UIView *subview in view.subviews) svpnLogTopStatusViews(subview, window, depth + 1);
}

static void svpnCaptureBreadcrumbViewHierarchy(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            svpnLogTopStatusViews(window, window, 0);
        }
        svpnBreadcrumbLog(@"view scan complete");
    });
}

static NSUserDefaults *svpnDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.82flex.singlevpnprefs"];
}

static void svpnApplyBreadcrumbOffset(UIView *view) {
    if (!view) return;
    CGFloat offset = _isEnabled ? _breadcrumbVerticalOffset : 0.0;
    view.transform = CGAffineTransformMakeTranslation(0.0, offset);
    [_breadcrumbViews addObject:view];
}

static void svpnRefreshBreadcrumbOffsets(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *view in _breadcrumbViews.allObjects) {
            svpnApplyBreadcrumbOffset(view);
        }
    });
}

static void svpnSampleTrafficUsage(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0 || !interfaces) {
        return;
    }

    NSMutableDictionary *currentBaselines = [NSMutableDictionary dictionary];
    for (struct ifaddrs *interface = interfaces; interface; interface = interface->ifa_next) {
        if (!interface->ifa_addr || interface->ifa_addr->sa_family != AF_LINK || !interface->ifa_data) {
            continue;
        }

        NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
        BOOL isWifi = [name isEqualToString:@"en0"];
        BOOL isCellular = [name hasPrefix:@"pdp_ip"];
        if (!isWifi && !isCellular) {
            continue;
        }

        const struct if_data *data = (const struct if_data *)interface->ifa_data;
        currentBaselines[name] = @{
            @"download": @((unsigned long long)data->ifi_ibytes),
            @"upload": @((unsigned long long)data->ifi_obytes),
            @"type": isWifi ? @"wifi" : @"cellular",
        };
    }
    freeifaddrs(interfaces);

    NSUserDefaults *defaults = svpnDefaults();
    NSDictionary *previousBaselines = [defaults dictionaryForKey:SVPNTrafficBaselinesKey];
    if (previousBaselines.count > 0) {
        __block unsigned long long cellularDownload = [[defaults objectForKey:SVPNCellularDownloadKey] unsignedLongLongValue];
        __block unsigned long long cellularUpload = [[defaults objectForKey:SVPNCellularUploadKey] unsignedLongLongValue];
        __block unsigned long long wifiDownload = [[defaults objectForKey:SVPNWifiDownloadKey] unsignedLongLongValue];
        __block unsigned long long wifiUpload = [[defaults objectForKey:SVPNWifiUploadKey] unsignedLongLongValue];

        [currentBaselines enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *current, BOOL *stop) {
            NSDictionary *previous = previousBaselines[name];
            if (!previous) {
                return;
            }

            unsigned long long currentDownload = [current[@"download"] unsignedLongLongValue];
            unsigned long long currentUpload = [current[@"upload"] unsignedLongLongValue];
            unsigned long long previousDownload = [previous[@"download"] unsignedLongLongValue];
            unsigned long long previousUpload = [previous[@"upload"] unsignedLongLongValue];
            unsigned long long downloadDelta = currentDownload >= previousDownload ? currentDownload - previousDownload : currentDownload;
            unsigned long long uploadDelta = currentUpload >= previousUpload ? currentUpload - previousUpload : currentUpload;

            if ([current[@"type"] isEqualToString:@"wifi"]) {
                wifiDownload += downloadDelta;
                wifiUpload += uploadDelta;
            } else {
                cellularDownload += downloadDelta;
                cellularUpload += uploadDelta;
            }
        }];

        [defaults setObject:@(cellularDownload) forKey:SVPNCellularDownloadKey];
        [defaults setObject:@(cellularUpload) forKey:SVPNCellularUploadKey];
        [defaults setObject:@(wifiDownload) forKey:SVPNWifiDownloadKey];
        [defaults setObject:@(wifiUpload) forKey:SVPNWifiUploadKey];
    }

    [defaults setObject:currentBaselines forKey:SVPNTrafficBaselinesKey];
    [defaults setObject:[NSDate date] forKey:@"TrafficLastUpdated"];
    [defaults synchronize];
}

static void svpnStartTrafficTimer(void) {
    svpnSampleTrafficUsage();
    _trafficTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(_trafficTimer, dispatch_time(DISPATCH_TIME_NOW, 60 * 60 * NSEC_PER_SEC), 60 * 60 * NSEC_PER_SEC, 5 * 60 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(_trafficTimer, ^{
        @autoreleasepool {
            svpnSampleTrafficUsage();
        }
    });
    dispatch_resume(_trafficTimer);
}

static void svpnTrafficRefreshRequested(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            svpnSampleTrafficUsage();
        }
    });
}

static NSString *svpnCompactTrafficValue(unsigned long long bytes) {
    static NSArray<NSString *> *units = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        units = @[ @"B", @"K", @"M", @"G", @"T", @"P" ];
    });

    double value = (double)bytes;
    NSUInteger unitIndex = 0;
    while (value >= 1024.0 && unitIndex < units.count - 1) {
        value /= 1024.0;
        unitIndex++;
    }
    return unitIndex == 0
        ? [NSString stringWithFormat:@"%llu%@", bytes, units[unitIndex]]
        : [NSString stringWithFormat:@"%.2f%@", value, units[unitIndex]];
}

static NSString *svpnTrafficSummary(void) {
    NSUserDefaults *defaults = svpnDefaults();
    NSString *(^fixedValue)(unsigned long long) = ^NSString *(unsigned long long bytes) {
        NSString *value = svpnCompactTrafficValue(bytes);
        if (value.length >= 8) {
            return value;
        }
        NSString *padding = [@"" stringByPaddingToLength:8 - value.length withString:@" " startingAtIndex:0];
        return [padding stringByAppendingString:value];
    };
    return [NSString stringWithFormat:@"  5G↑%@   5G↓%@\nWiFi↑%@ WiFi↓%@",
        fixedValue([[defaults objectForKey:SVPNCellularUploadKey] unsignedLongLongValue]),
        fixedValue([[defaults objectForKey:SVPNCellularDownloadKey] unsignedLongLongValue]),
        fixedValue([[defaults objectForKey:SVPNWifiUploadKey] unsignedLongLongValue]),
        fixedValue([[defaults objectForKey:SVPNWifiDownloadKey] unsignedLongLongValue])];
}

static const void *SVPNTrafficLabelKey = &SVPNTrafficLabelKey;

static UIWindow *svpnSettingsKeyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return nil;
}

static UILabel *svpnFindSettingsTitleLabel(UIView *view) {
    UILabel *best = nil;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if ([label.text isEqualToString:@"设置"] || [label.text isEqualToString:@"Settings"]) {
            best = label;
        }
    }
    for (UIView *subview in view.subviews) {
        UILabel *found = svpnFindSettingsTitleLabel(subview);
        if (found && (!best || found.font.pointSize > best.font.pointSize)) {
            best = found;
        }
    }
    return best;
}

static void svpnInstallIndependentSettingsTrafficLabel(void) {
    UIWindow *window = svpnSettingsKeyWindow();
    if (!window) {
        return;
    }

    UILabel *titleLabel = svpnFindSettingsTitleLabel(window);
    UILabel *label = objc_getAssociatedObject(window, SVPNTrafficLabelKey);
    if (!titleLabel) {
        label.hidden = YES;
        _settingsRootVisible = NO;
        return;
    }

    if (!_settingsRootVisible) {
        _settingsRootVisible = YES;
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.82flex.singlevpnprefs/refresh-traffic"),
            NULL,
            NULL,
            YES
        );
    }

    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.backgroundColor = UIColor.clearColor;
        label.textAlignment = NSTextAlignmentRight;
        label.textColor = UIColor.secondaryLabelColor;
        label.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
        label.numberOfLines = 2;
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.72;
        label.userInteractionEnabled = NO;
        label.accessibilityIdentifier = @"SingleVPNTrafficSummary";
        objc_setAssociatedObject(window, SVPNTrafficLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGRect titleFrame = [titleLabel convertRect:titleLabel.bounds toView:window];
    CGFloat left = CGRectGetMaxX(titleFrame) + 12.0;
    if (label.superview != titleLabel) {
        [label removeFromSuperview];
        [titleLabel addSubview:label];
    }
    label.hidden = titleLabel.font.pointSize < 30.0;
    label.frame = CGRectMake(titleLabel.bounds.size.width + 12.0, 0.0,
        MAX(0.0, window.bounds.size.width - left - 16.0), titleLabel.bounds.size.height);
    label.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    label.text = svpnTrafficSummary();
}

static void svpnStartSettingsOverlayTimer(void) {
    svpnInstallIndependentSettingsTrafficLabel();
    _settingsOverlayTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_settingsOverlayTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
    dispatch_source_set_event_handler(_settingsOverlayTimer, ^{
        svpnInstallIndependentSettingsTrafficLabel();
    });
    dispatch_resume(_settingsOverlayTimer);
}

static UIColor *svpnColorWithHexString(NSString *hexString) {
    if (!hexString) {
        return nil;
    }
    return [UIColor svpn_colorWithExternalRepresentation:hexString];
}

static UIColor *svpnColorWithTextColor(UIColor *textColor) {
    return [textColor svpn_isDarkColor] ? _lightReplacementColor : _darkReplacementColor;
}

static void ReloadPrefs() {
    static NSUserDefaults *prefs = nil;
    if (!prefs) {
        prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.82flex.singlevpnprefs"];
    }

    NSMutableDictionary *settings = [[prefs dictionaryRepresentation] mutableCopy] ?: [NSMutableDictionary dictionary];
    CFStringRef appID = CFSTR("com.82flex.singlevpnprefs");
    CFPreferencesAppSynchronize(appID);
    CFDictionaryRef sharedValues = CFPreferencesCopyMultiple(NULL, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (sharedValues) {
        [settings addEntriesFromDictionary:(__bridge NSDictionary *)sharedValues];
        CFRelease(sharedValues);
    }
    _isEnabled = settings[@"IsEnabled"] ? [settings[@"IsEnabled"] boolValue] : YES;
    _isEnabledReversed = settings[@"IsEnabledReversed"] ? [settings[@"IsEnabledReversed"] boolValue] : NO;
    _isForce5GAEnabled = settings[@"IsForce5GAEnabled"] ? [settings[@"IsForce5GAEnabled"] boolValue] : NO;
    _breadcrumbVerticalOffset = settings[@"BreadcrumbVerticalOffset"] ? [settings[@"BreadcrumbVerticalOffset"] doubleValue] : 0.0;

    _lightReplacementColor = svpnColorWithHexString(settings[@"ForegroundColorLight"]) ?: [UIColor colorWithRed:0.19607843137254902 green:0.7803921568627451 blue:0.34901960784313724 alpha:1];
    _darkReplacementColor = svpnColorWithHexString(settings[@"ForegroundColorDark"]) ?: [UIColor colorWithRed:0.17254901960784313 green:0.8156862745098039 blue:0.3411764705882353 alpha:1];
    if (svpnIsPreferenceAuthorityProcess()) {
        svpnPublishBreadcrumbState();
    } else {
        svpnConsumeBreadcrumbState();
    }
    svpnRefreshBreadcrumbOffsets();
}

%group SingleVPN_16

%hook _UIStatusBarWifiItem

- (id)applyUpdate:(_UIStatusBarItemUpdate *)update toDisplayItem:(_UIStatusBarDisplayItem *)displayItem {
    _isVPNEnabled = update.data.vpnEntry.enabled;

    id result = %orig;

    UIColor *originalColor = update.styleAttributes.textColor;
    UIColor *newColor = nil;

    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision) {
        newColor = svpnColorWithTextColor(originalColor);
    }

    if (!newColor) { newColor = update.styleAttributes.imageTintColor ?: originalColor; }

    for (_UIStatusBarDisplayItem *item in self.displayItems.allValues) {
        %orig(update, item);

        if (item.view == self.networkIconView && [item.view isKindOfClass:%c(_UIStatusBarImageView)]) {
            _UIStatusBarImageView *imageView = (_UIStatusBarImageView *)item.view;
            [imageView setTintColor:newColor];
        }
    }

    return result;
}

- (UIColor *)_fillColorForUpdate:(_UIStatusBarItemUpdate *)update entry:(_UIStatusBarDataWifiEntry *)entry {
    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision) { 
        return svpnColorWithTextColor(update.styleAttributes.textColor);
    } else {
        return %orig; 
    }
}

%end

%hook _UIStatusBarCellularItem

- (id)applyUpdate:(_UIStatusBarItemUpdate *)update toDisplayItem:(_UIStatusBarDisplayItem *)displayItem {
    _isVPNEnabled = update.data.vpnEntry.enabled;

    id result = %orig;

    UIColor *originalColor = update.styleAttributes.textColor;
    UIColor *newColor = nil;

    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision) {
        newColor = svpnColorWithTextColor(originalColor);
    }

    if (!newColor) { newColor = originalColor; }

    for (_UIStatusBarDisplayItem *item in self.displayItems.allValues) {
        _UIStatusBarStringView *stringView = nil;

        if ([item.view isKindOfClass:%c(_UIStatusBarCellularNetworkTypeView)]) {
            stringView = ((_UIStatusBarCellularNetworkTypeView *)item.view).stringView;
        } else if ([item.view isKindOfClass:%c(_UIStatusBarStringView)]) {
            stringView = (_UIStatusBarStringView *)item.view;
        }

        if (IsNetworkTypeText(stringView.text)) {
            [stringView setTextColor:newColor];
        } else {
            [stringView setTextColor:originalColor];
        }
    }

    return result;
}

%end


%hook _UIStatusBarStringView

- (void)applyStyleAttributes:(_UIStatusBarStyleAttributes *)styleAttrs {
    %orig;

    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision && IsNetworkTypeText(self.text)) {
        [self setTextColor:svpnColorWithTextColor(styleAttrs.textColor)];
    }
}

%end

%end // SingleVPN_16

%group SingleVPN_17

%hook STUIStatusBar

- (void)_updateWithAggregatedData:(STStatusBarData *)data {
    BOOL changed = data.vpnEntry;
    STStatusBarData *currentData = [self currentData];
    if (changed && currentData.cellularEntry && !data.cellularEntry) {
        data = [data dataByReplacingEntry:[currentData.cellularEntry copy] forKey:@"cellularEntry"];
    }
    if (changed && currentData.secondaryCellularEntry && !data.secondaryCellularEntry) {
        data = [data dataByReplacingEntry:[currentData.secondaryCellularEntry copy] forKey:@"secondaryCellularEntry"];
    }
    if (changed && currentData.wifiEntry && !data.wifiEntry) {
        data = [data dataByReplacingEntry:[currentData.wifiEntry copy] forKey:@"wifiEntry"];
    }

    _isVPNEnabled = currentData.vpnEntry.enabled || data.vpnEntry.enabled;
    %orig;
}

- (void)_updateWithData:(STStatusBarData *)data completionHandler:(id)a4 {
    BOOL changed = data.vpnEntry;
    STStatusBarData *currentData = [self currentData];
    if (changed && currentData.cellularEntry && !data.cellularEntry) {
        data = [data dataByReplacingEntry:[currentData.cellularEntry copy] forKey:@"cellularEntry"];
    }
    if (changed && currentData.secondaryCellularEntry && !data.secondaryCellularEntry) {
        data = [data dataByReplacingEntry:[currentData.secondaryCellularEntry copy] forKey:@"secondaryCellularEntry"];
    }
    if (changed && currentData.wifiEntry && !data.wifiEntry) {
        data = [data dataByReplacingEntry:[currentData.wifiEntry copy] forKey:@"wifiEntry"];
    }

    _isVPNEnabled = currentData.vpnEntry.enabled || data.vpnEntry.enabled;
    %orig;
}

%end

%hook STUIStatusBarCellularNetworkTypeView

- (void)setText:(NSString *)text prefixLength:(NSInteger)prefixLength withStyleAttributes:(STUIStatusBarStyleAttributes *)styleAttrs forType:(NSInteger)type animated:(BOOL)animated {
    if (!IsNetworkTypeText(text) || !_isForce5GAEnabled || !Is5GPlusNetworkTypeText(text)) {
        %orig;
        if (@available(iOS 16, *)) {
            if (_isForce5GAEnabled && !self.widthConstraint.active) {
                objc_setAssociatedObject(self, @selector(widthConstraint), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                self.widthConstraint.active = YES;
            }
        }
        return;
    }

    if (@available(iOS 16, *)) {
        %orig(@"5G", 2, styleAttrs, type, NO);

        [self.stringView svpnSet5GAdvancedText];

        NSAttributedString *attributedText = self.stringView.attributedText;
        self.widthConstraint.active = NO;

        NSLayoutConstraint *newWidthConstraint = [NSLayoutConstraint constraintWithItem:self attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:0];
        newWidthConstraint.constant = [attributedText size].width * 0.9;
        newWidthConstraint.priority = UILayoutPriorityRequired;
        newWidthConstraint.active = YES;

        objc_setAssociatedObject(self, @selector(widthConstraint), newWidthConstraint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        %orig;
    }
}

%end

%hook STUIStatusBarStringView

%new
- (void)svpnSet5GAdvancedText {
    if (@available(iOS 16, *)) {
        UIFont *font = self.font;
        if (!font) {
            return;
        }

        UIColor *textColor = self.textColor;
        if (!textColor) {
            return;
        }

        NSString *newText = @"5GA";
        NSInteger prefixLength = 2;
        NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:newText attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: textColor,
        }];

        NSMutableDictionary *traits = [[font.fontDescriptor objectForKey:UIFontDescriptorTraitsAttribute] mutableCopy] ?: [NSMutableDictionary dictionary];
        traits[UIFontWidthTrait] = @(UIFontWidthCondensed / 1.5);
        traits[UIFontWeightTrait] = @(UIFontWeightSemibold);

        UIFontDescriptor *condensedDescriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorTraitsAttribute: traits}];
        UIFont *condensedFont = [UIFont fontWithDescriptor:condensedDescriptor size:0];
        UIFont *smallerCondensedFont = [condensedFont fontWithSize:condensedFont.pointSize * 0.7];

        [attributedText addAttribute:NSFontAttributeName value:condensedFont range:NSMakeRange(0, prefixLength)];
        [attributedText addAttribute:NSFontAttributeName value:smallerCondensedFont range:NSMakeRange(prefixLength, attributedText.length - prefixLength)];

        self.attributedText = attributedText;
    }
}

%new
- (void)svpnApply5GAdvancedAttributesIfNeeded {
    if (@available(iOS 16, *)) {
        if (!_isForce5GAEnabled || !Is5GAdvancedNetworkTypeText(self.text)) {
            return;
        }

        NSAttributedString *currentAttributedText = self.attributedText;
        if (currentAttributedText.length == 3) {
            UIFont *currentPrefixFont = [currentAttributedText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil];
            UIFont *currentSuffixFont = [currentAttributedText attribute:NSFontAttributeName atIndex:2 effectiveRange:nil];
            UIColor *currentTextColor = [currentAttributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil];
            BOOL hasSmallSuffix = currentPrefixFont && currentSuffixFont && currentSuffixFont.pointSize < currentPrefixFont.pointSize;
            if (hasSmallSuffix && [currentTextColor isEqual:self.textColor]) {
                return;
            }
        }

        [self svpnSet5GAdvancedText];
    }
}

- (void)applyStyleAttributes:(STUIStatusBarStyleAttributes *)styleAttrs {
    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision && IsNetworkTypeText(self.text)) {
        styleAttrs = [styleAttrs copy];
        [styleAttrs setTextColor:svpnColorWithTextColor(styleAttrs.textColor)];
    }

    %orig;
    [self svpnApply5GAdvancedAttributesIfNeeded];
}

- (void)setText:(NSString *)text {
    if (_isForce5GAEnabled && Is5GAdvancedNetworkTypeText(text) && self.font && self.textColor) {
        [self svpnSet5GAdvancedText];
        return;
    }

    %orig;

    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision && IsNetworkTypeText(text)) {
        [self setTextColor:svpnColorWithTextColor(self.textColor)];
    }

    [self svpnApply5GAdvancedAttributesIfNeeded];
}

%end

%hook STUIStatusBarWifiSignalView

- (void)setActiveColor:(UIColor *)activeColor {
    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision) {
        activeColor = svpnColorWithTextColor(activeColor);
    }

    %orig;
}

- (void)setInactiveColor:(UIColor *)inactiveColor {
    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision) {
        inactiveColor = [svpnColorWithTextColor(inactiveColor) colorWithAlphaComponent:0.2];
    }

    %orig;
}

- (void)applyStyleAttributes:(STUIStatusBarStyleAttributes *)styleAttrs {
    BOOL decision = _isEnabledReversed ? !_isVPNEnabled : _isVPNEnabled;
    if (decision) {
        styleAttrs = [styleAttrs copy];
        UIColor *newColor = svpnColorWithTextColor(styleAttrs.textColor);
        [styleAttrs setImageTintColor:newColor];
        [styleAttrs setImageDimmedTintColor:[newColor colorWithAlphaComponent:0.2]];
    }

    %orig;
}

%end

%end // SingleVPN_17

static void svpnDumpSpringBoardStatusRuntimeOnce(void);

%group SingleVPN_BreadcrumbDiagnostic

%hook SBDeviceApplicationSceneStatusBarBreadcrumbProvider

- (id)breadcrumbActionsForActivatingSceneEntity:(id)entity withTransitionContext:(id)context {
    id result = %orig;
    svpnBreadcrumbLog(@"provider actions class=%@ count=%lu entity=%@ context=%@", NSStringFromClass([result class]), (unsigned long)([result respondsToSelector:@selector(count)] ? [result count] : 0), NSStringFromClass([entity class]), NSStringFromClass([context class]));
    svpnDumpSpringBoardStatusRuntimeOnce();
    svpnCaptureBreadcrumbViewHierarchy();
    return result;
}

%end

%end // SingleVPN_BreadcrumbDiagnostic

%group SingleVPN_AppBreadcrumbDiagnostic

%hook UIStatusBarSystemNavigationItemView

- (void)layoutSubviews {
    %orig;
    CGFloat offset = _isEnabled ? _breadcrumbVerticalOffset : 0.0;
    svpnApplyBreadcrumbOffset(self);
    NSNumber *lastOffset = objc_getAssociatedObject(self, @selector(layoutSubviews));
    if (!lastOffset || fabs(lastOffset.doubleValue - offset) > 0.01) {
        objc_setAssociatedObject(self, @selector(layoutSubviews), @(offset), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        svpnBreadcrumbLog(@"system navigation layout applied class=%@ frame=%@ offset=%.2f enabled=%d", NSStringFromClass(self.class), NSStringFromCGRect(self.frame), offset, _isEnabled);
    }
}

%end

%end // SingleVPN_AppBreadcrumbDiagnostic

static void svpnDumpRuntimeShape(Class cls) {
    if (!cls) return;
    svpnBreadcrumbLog(@"shape class=%@ superclass=%@", NSStringFromClass(cls), NSStringFromClass(class_getSuperclass(cls)));
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int index = 0; index < methodCount; index++) {
        svpnBreadcrumbLog(@"shape method class=%@ selector=%@ types=%s", NSStringFromClass(cls), NSStringFromSelector(method_getName(methods[index])), method_getTypeEncoding(methods[index]));
    }
    free(methods);
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(cls, &ivarCount);
    for (unsigned int index = 0; index < ivarCount; index++) {
        svpnBreadcrumbLog(@"shape ivar class=%@ name=%s type=%s", NSStringFromClass(cls), ivar_getName(ivars[index]), ivar_getTypeEncoding(ivars[index]));
    }
    free(ivars);
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
    for (unsigned int index = 0; index < propertyCount; index++) {
        svpnBreadcrumbLog(@"shape property class=%@ name=%s attrs=%s", NSStringFromClass(cls), property_getName(properties[index]), property_getAttributes(properties[index]));
    }
    free(properties);
}

static void svpnDumpBreadcrumbSystemShape(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *names = @[
            @"UIStatusBarBreadcrumbItemView",
            @"_UIStatusBarNavigationItem",
            @"_UIStatusBarDisplayItemPlacement",
            @"_UIStatusBarVisualProvider_Phone",
            @"UIStatusBarLayoutManager",
            @"UIStatusBarServer"
        ];
        for (NSString *name in names) svpnDumpRuntimeShape(NSClassFromString(name));
        svpnBreadcrumbLog(@"shape dump complete");
    });
}

static void svpnDumpSpringBoardNavigationClasses(void) {
    int classCount = objc_getClassList(NULL, 0);
    if (classCount <= 0) return;
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)classCount, sizeof(Class));
    classCount = objc_getClassList(classes, classCount);
    svpnBreadcrumbLog(@"springboard navigation class scan count=%d", classCount);
    for (int index = 0; index < classCount; index++) {
        NSString *name = NSStringFromClass(classes[index]);
        NSString *lower = name.lowercaseString;
        BOOL relevantName = [lower containsString:@"breadcrumb"] || [lower containsString:@"navigation"];
        BOOL statusRelated = [lower containsString:@"statusbar"] || [name hasPrefix:@"STUI"] || [name hasPrefix:@"SB"];
        if (relevantName && statusRelated) {
            svpnBreadcrumbLog(@"springboard navigation candidate=%@", name);
            svpnDumpRuntimeShape(classes[index]);
        }
    }
    free(classes);
    svpnBreadcrumbLog(@"springboard navigation class scan complete");
}

static void svpnDumpSpringBoardStatusRuntimeOnce(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        svpnBreadcrumbLog(@"event-time status runtime dump begin");
        NSArray<NSString *> *names = @[
            @"STUIStatusBar", @"STUIStatusBarForegroundView", @"STUIStatusBarDisplayItem",
            @"STUIStatusBarItem", @"STUIStatusBarIdentifier", @"STUIStatusBarImageView",
            @"STUIStatusBarStringView", @"STUIStatusBarVisualProvider_Phone",
            @"SBDeviceApplicationSceneStatusBarBreadcrumbProvider"
        ];
        for (NSString *name in names) {
            Class cls = NSClassFromString(name);
            svpnBreadcrumbLog(@"event-time class name=%@ present=%d", name, cls != Nil);
            if (cls) svpnDumpRuntimeShape(cls);
        }
        svpnDumpSpringBoardNavigationClasses();
        svpnBreadcrumbLog(@"event-time status runtime dump complete");
    });
}

static void svpnInstallAppBreadcrumbDiagnostic(NSUInteger attempt) {
    Class navigationClass = NSClassFromString(@"UIStatusBarSystemNavigationItemView");
    if (navigationClass) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            %init(SingleVPN_AppBreadcrumbDiagnostic);
            svpnBreadcrumbLog(@"system navigation hook installed class=%@ offset=%.2f enabled=%d", NSStringFromClass(navigationClass), _breadcrumbVerticalOffset, _isEnabled);
            svpnDumpBreadcrumbSystemShape();
        });
        return;
    }
    if (attempt < 40) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            svpnInstallAppBreadcrumbDiagnostic(attempt + 1);
        });
    }
}

static void svpnInstallBreadcrumbDiagnostic(NSUInteger attempt) {
    Class provider = NSClassFromString(@"SBDeviceApplicationSceneStatusBarBreadcrumbProvider");
    SEL selector = @selector(breadcrumbActionsForActivatingSceneEntity:withTransitionContext:);
    BOOL selectorPresent = provider && class_getInstanceMethod(provider, selector) != NULL;
    svpnBreadcrumbLog(@"diagnostic probe attempt=%lu class=%d selector=%d enabled=%d offset=%.2f", (unsigned long)attempt, provider != Nil, selectorPresent, _isEnabled, _breadcrumbVerticalOffset);
    if (provider && !selectorPresent && attempt == 0) {
        for (Class current = provider; current; current = class_getSuperclass(current)) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(current, &count);
            svpnBreadcrumbLog(@"method dump class=%@ count=%u", NSStringFromClass(current), count);
            for (unsigned int index = 0; index < count; index++) {
                NSString *name = NSStringFromSelector(method_getName(methods[index]));
                NSString *lower = name.lowercaseString;
                if ([lower containsString:@"breadcrumb"] || [lower containsString:@"scene"] || [lower containsString:@"transition"] || [lower containsString:@"activat"] || [lower containsString:@"statusbar"]) {
                    svpnBreadcrumbLog(@"candidate class=%@ selector=%@ types=%s", NSStringFromClass(current), name, method_getTypeEncoding(methods[index]));
                }
            }
            free(methods);
        }
    }
    if (selectorPresent) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            %init(SingleVPN_BreadcrumbDiagnostic);
            svpnBreadcrumbLog(@"diagnostic hook installed");
        });
        return;
    }
    if (attempt < 20) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        svpnInstallBreadcrumbDiagnostic(attempt + 1);
    });
}

%ctor {
    _breadcrumbViews = [NSHashTable weakObjectsHashTable];
    ReloadPrefs();

    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if ([bundleIdentifier isEqualToString:@"com.apple.Preferences"]) {
        svpnStartSettingsOverlayTimer();
        return;
    }
    if (![bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        svpnBreadcrumbLog(@"loaded app version=2.1-41 bundle=%@ executable=%@ offset=%.2f enabled=%d state=%d", bundleIdentifier, NSProcessInfo.processInfo.processName, _breadcrumbVerticalOffset, _isEnabled, svpnConsumeBreadcrumbState());
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)ReloadPrefs, CFSTR("com.82flex.singlevpnprefs/breadcrumb-state-updated"), NULL, CFNotificationSuspensionBehaviorCoalesce);
        svpnInstallAppBreadcrumbDiagnostic(0);
        return;
    }

    svpnBreadcrumbLog(@"loaded version=2.1-43 bundle=%@ enabled=%d offset=%.2f", bundleIdentifier, _isEnabled, _breadcrumbVerticalOffset);
    svpnInstallBreadcrumbDiagnostic(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        svpnDumpSpringBoardNavigationClasses();
    });

    svpnStartTrafficTimer();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        svpnTrafficRefreshRequested,
        CFSTR("com.82flex.singlevpnprefs/refresh-traffic"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
    if (!_isEnabled) {
        return;
    }

    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), 
        NULL, 
        (CFNotificationCallback)ReloadPrefs, 
        CFSTR("com.82flex.singlevpnprefs/saved"), 
        NULL, 
        CFNotificationSuspensionBehaviorCoalesce
    );

    if (@available(iOS 17, *)) {
        dlopen("/System/Library/PrivateFrameworks/StatusStatusUI.framework/StatusStatusUI", RTLD_LAZY);
        %init(SingleVPN_17);
    } else {
        %init(SingleVPN_16);
    }
}
