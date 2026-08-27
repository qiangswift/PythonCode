#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <objc/runtime.h>

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

@interface STUIStatusBarImageView : UIImageView
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
static const void *SVPNNavigationShiftedFrameKey = &SVPNNavigationShiftedFrameKey;

static NSString *const SVPNTrafficBaselinesKey = @"TrafficBaselines";
static NSString *const SVPNCellularDownloadKey = @"TrafficCellularDownload";
static NSString *const SVPNCellularUploadKey = @"TrafficCellularUpload";
static NSString *const SVPNWifiDownloadKey = @"TrafficWifiDownload";
static NSString *const SVPNWifiUploadKey = @"TrafficWifiUpload";

static BOOL svpnIsStatusBarNavigationView(STUIStatusBarStringView *view, CGRect proposedFrame) {
    NSString *text = view.text ?: @"";
    if ([text rangeOfString:@"◀"].location != NSNotFound) return YES;
    if (!text.length || [text rangeOfString:@"\n"].location != NSNotFound) return NO;
    BOOL bottomLeadingGeometry = proposedFrame.size.height > 0.0 && proposedFrame.size.height <= 22.0
        && proposedFrame.origin.y >= 20.0 && proposedFrame.origin.x < 130.0;
    return bottomLeadingGeometry && !IsNetworkTypeText(text);
}

static void svpnAllowStatusBarNavigationOverflow(UIView *view) {
    UIView *candidate = view.superview;
    NSUInteger depth = 0;
    while (candidate && depth < 8) {
        candidate.clipsToBounds = NO;
        candidate.layer.masksToBounds = NO;
        if ([candidate isKindOfClass:NSClassFromString(@"STUIStatusBar")]) {
            break;
        }
        candidate = candidate.superview;
        depth++;
    }
}

static void svpnApplyStatusBarNavigationOffset(STUIStatusBarStringView *view) {
    NSNumber *navigationMarker = view ? objc_getAssociatedObject(view, SVPNNavigationShiftedFrameKey) : nil;
    if (!view || (!navigationMarker.boolValue && !svpnIsStatusBarNavigationView(view, view.frame))) return;
    svpnAllowStatusBarNavigationOverflow(view);
    view.clipsToBounds = NO;
    view.layer.masksToBounds = NO;
    CGFloat offset = _isEnabled ? _breadcrumbVerticalOffset : 0.0;
    CGRect bounds = view.bounds;
    bounds.origin.y = 0.0;
    view.bounds = bounds;
    view.layer.transform = CATransform3DMakeTranslation(0.0, offset, 0.0);
}

static NSUserDefaults *svpnDefaults(void) {
    return [[NSUserDefaults alloc] initWithSuiteName:@"com.82flex.singlevpnprefs"];
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

static const void *SVPNTrafficLabelKey = &SVPNTrafficLabelKey;
static const void *SVPNTrafficLeftLabelKey = &SVPNTrafficLeftLabelKey;
static const void *SVPNTrafficRightLabelKey = &SVPNTrafficRightLabelKey;
static const void *SVPNTrafficLeftValueLabelKey = &SVPNTrafficLeftValueLabelKey;
static const void *SVPNTrafficRightValueLabelKey = &SVPNTrafficRightValueLabelKey;

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
    UIView *trafficView = objc_getAssociatedObject(window, SVPNTrafficLabelKey);
    if (!titleLabel) {
        trafficView.hidden = YES;
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

    if (!trafficView) {
        trafficView = [[UIView alloc] initWithFrame:CGRectZero];
        trafficView.backgroundColor = UIColor.clearColor;
        trafficView.userInteractionEnabled = NO;
        trafficView.accessibilityIdentifier = @"SingleVPNTrafficSummary";

        UIFont *font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular];
        NSArray<NSValue *> *labelKeys = @[
            [NSValue valueWithPointer:SVPNTrafficLeftLabelKey],
            [NSValue valueWithPointer:SVPNTrafficLeftValueLabelKey],
            [NSValue valueWithPointer:SVPNTrafficRightLabelKey],
            [NSValue valueWithPointer:SVPNTrafficRightValueLabelKey]
        ];
        for (NSUInteger index = 0; index < labelKeys.count; index++) {
            UILabel *columnLabel = [[UILabel alloc] initWithFrame:CGRectZero];
            columnLabel.backgroundColor = UIColor.clearColor;
            columnLabel.textAlignment = (index == 1 || index == 3) ? NSTextAlignmentRight : NSTextAlignmentLeft;
            columnLabel.textColor = UIColor.secondaryLabelColor;
            columnLabel.font = font;
            columnLabel.numberOfLines = 2;
            columnLabel.adjustsFontSizeToFitWidth = YES;
            columnLabel.minimumScaleFactor = 0.76;
            columnLabel.userInteractionEnabled = NO;
            [trafficView addSubview:columnLabel];
            objc_setAssociatedObject(trafficView, labelKeys[index].pointerValue,
                columnLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(window, SVPNTrafficLabelKey, trafficView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGRect titleFrame = [titleLabel convertRect:titleLabel.bounds toView:window];
    CGFloat trafficLeadingSpacing = 24.0;
    CGFloat left = CGRectGetMaxX(titleFrame) + trafficLeadingSpacing;
    if (trafficView.superview != titleLabel) {
        [trafficView removeFromSuperview];
        [titleLabel addSubview:trafficView];
    }
    trafficView.hidden = titleLabel.font.pointSize < 30.0;
    trafficView.frame = CGRectMake(titleLabel.bounds.size.width + trafficLeadingSpacing, 0.0,
        MAX(0.0, window.bounds.size.width - left - 16.0), titleLabel.bounds.size.height);
    trafficView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    UILabel *leftLabel = objc_getAssociatedObject(trafficView, SVPNTrafficLeftLabelKey);
    UILabel *leftValueLabel = objc_getAssociatedObject(trafficView, SVPNTrafficLeftValueLabelKey);
    UILabel *rightLabel = objc_getAssociatedObject(trafficView, SVPNTrafficRightLabelKey);
    UILabel *rightValueLabel = objc_getAssociatedObject(trafficView, SVPNTrafficRightValueLabelKey);
    NSUserDefaults *defaults = svpnDefaults();
    leftLabel.text = @"5G↑：\n5G↓：";
    leftValueLabel.text = [NSString stringWithFormat:@"%@\n%@",
        svpnCompactTrafficValue([[defaults objectForKey:SVPNCellularUploadKey] unsignedLongLongValue]),
        svpnCompactTrafficValue([[defaults objectForKey:SVPNCellularDownloadKey] unsignedLongLongValue])];
    rightLabel.text = @"WiFi↑：\nWiFi↓：";
    rightValueLabel.text = [NSString stringWithFormat:@"%@\n%@",
        svpnCompactTrafficValue([[defaults objectForKey:SVPNWifiUploadKey] unsignedLongLongValue]),
        svpnCompactTrafficValue([[defaults objectForKey:SVPNWifiDownloadKey] unsignedLongLongValue])];

    CGFloat valueGap = 2.0;
    CGFloat groupGap = 10.0;
    CGSize fittingSize = CGSizeMake(CGFLOAT_MAX, trafficView.bounds.size.height);
    CGFloat leftPrefixWidth = ceil([leftLabel sizeThatFits:fittingSize].width);
    CGFloat leftValueWidth = ceil([leftValueLabel sizeThatFits:fittingSize].width);
    CGFloat rightPrefixWidth = ceil([rightLabel sizeThatFits:fittingSize].width);
    CGFloat rightValueWidth = ceil([rightValueLabel sizeThatFits:fittingSize].width);
    CGFloat x = 0.0;
    leftLabel.frame = CGRectMake(x, 0.0, leftPrefixWidth, trafficView.bounds.size.height);
    x += leftPrefixWidth + valueGap;
    leftValueLabel.frame = CGRectMake(x, 0.0, leftValueWidth, trafficView.bounds.size.height);
    x += leftValueWidth + groupGap;
    rightLabel.frame = CGRectMake(x, 0.0, rightPrefixWidth, trafficView.bounds.size.height);
    x += rightPrefixWidth + valueGap;
    rightValueLabel.frame = CGRectMake(x, 0.0, rightValueWidth, trafficView.bounds.size.height);
    x += rightValueWidth;

    CGFloat wifiCenterX = window.bounds.size.width * 0.805;
    CGFloat anchoredOriginX = wifiCenterX - CGRectGetMinX(titleFrame) - x;
    CGFloat minimumOriginX = titleLabel.bounds.size.width + trafficLeadingSpacing;
    CGRect anchoredFrame = trafficView.frame;
    anchoredFrame.origin.x = MAX(minimumOriginX, anchoredOriginX);
    anchoredFrame.size.width = MAX(x,
        window.bounds.size.width - CGRectGetMinX(titleFrame) - anchoredFrame.origin.x - 16.0);
    trafficView.frame = anchoredFrame;
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
    _breadcrumbVerticalOffset = settings[@"BreadcrumbVerticalOffset"] ? [settings[@"BreadcrumbVerticalOffset"] doubleValue] : 7.6;

    _lightReplacementColor = svpnColorWithHexString(settings[@"ForegroundColorLight"]) ?: [UIColor colorWithRed:0.19607843137254902 green:0.7803921568627451 blue:0.34901960784313724 alpha:1];
    _darkReplacementColor = svpnColorWithHexString(settings[@"ForegroundColorDark"]) ?: [UIColor colorWithRed:0.17254901960784313 green:0.8156862745098039 blue:0.3411764705882353 alpha:1];
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

- (void)setFrame:(CGRect)frame {
    BOOL navigationView = svpnIsStatusBarNavigationView(self, frame);
    objc_setAssociatedObject(self, SVPNNavigationShiftedFrameKey,
        navigationView ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(frame);
    if (navigationView) svpnApplyStatusBarNavigationOffset(self);
}

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
    svpnApplyStatusBarNavigationOffset(self);
}

- (void)layoutSubviews {
    %orig;
    svpnApplyStatusBarNavigationOffset(self);
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

%ctor {
    ReloadPrefs();

    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if ([bundleIdentifier isEqualToString:@"com.apple.Preferences"]) {
        svpnStartSettingsOverlayTimer();
        return;
    }
    if (![bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;

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
