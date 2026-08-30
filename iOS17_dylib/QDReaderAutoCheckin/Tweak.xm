#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>

static NSString *const QDRTargetBundle = @"m.qidian.QDReaderAppStore";
static NSString *const QDREnterpriseBundle = @"m.qidian.QDReaderQiYe";
static NSString *const QDRPrefsSuite = @"com.swiftss.qdreaderautocheckin.runtime";
// Do not trust the legacy completion key: versions through 1.2.7 wrote it
// when JavaScript merely called $done(), even if no task request was made.
static NSString *const QDRLastCompletedKey = @"verifiedLastCompletedDateV2";
static const void *QDRShelfNativeFoldKey = &QDRShelfNativeFoldKey;

@interface QDRShelfViewController : UIViewController
@end

extern "C" void QDRInvokeSwiftVoidClosure(void *function, void *context);

static NSString *QDRLogPath(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"QDReaderAutoCheckin.log"];
}

static void QDRLog(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss Z";
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:NSDate.date], body ?: @""];
    @synchronized (NSFileManager.defaultManager) {
        if (![NSFileManager.defaultManager fileExistsAtPath:QDRLogPath()]) [line writeToFile:QDRLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:QDRLogPath()];
            [handle seekToEndOfFile]; [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [handle closeFile];
        }
    }
}

static NSString *QDRRedactedExcerpt(NSData *data) {
    if (!data.length) return @"<empty>";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"<non-utf8>";
    if (text.length > 1600) text = [[text substringToIndex:1600] stringByAppendingString:@"…"];
    NSArray *patterns = @[
        @"(?i)(\\\"?(?:cookie|qdheader|token|sessionkey|signature|sign|authorization)\\\"?\\s*[:=]\\s*\\\")[^\\\"]*",
        @"(?i)((?:cookie|qdheader|token|sessionkey|signature|authorization)=)[^&\\s]+"
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        text = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"$1<redacted>"];
    }
    return [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

static NSURL *QDRCreateURL(NSString *value, NSURL *baseURL) {
    if (![value isKindOfClass:NSString.class] || value.length == 0) return nil;
    CFURLRef url = CFURLCreateWithString(kCFAllocatorDefault, (__bridge CFStringRef)value, baseURL ? (__bridge CFURLRef)baseURL : NULL);
    return CFBridgingRelease(url);
}

static BOOL QDRTapSplashSkipInView(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.01) return NO;
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        NSString *text = @"";
        if ([control isKindOfClass:UIButton.class]) text = [(UIButton *)control titleForState:UIControlStateNormal] ?: @"";
        NSString *label = control.accessibilityLabel ?: @"";
        NSString *value = control.accessibilityValue ?: @"";
        NSString *joined = [NSString stringWithFormat:@"%@ %@ %@", text, label, value].lowercaseString;
        if ([joined containsString:@"跳过"] || [joined containsString:@"skip"]) {
            [control sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
    }
    for (UIView *child in view.subviews.reverseObjectEnumerator) if (QDRTapSplashSkipInView(child)) return YES;
    return NO;
}

static void QDRScheduleSplashSkip(NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL tapped = NO;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
                if (QDRTapSplashSkipInView(window)) { tapped = YES; break; }
            }
            if (tapped) break;
        }
        if (!tapped && attempt < 25) QDRScheduleSplashSkip(attempt + 1);
    });
}

@interface QDRAutoRunner : NSObject
@property(nonatomic) dispatch_queue_t queue;
@property(nonatomic) BOOL running;
@property(nonatomic) NSInteger callbackSeed;
@property(nonatomic, copy) NSString *pendingNotice;
@property(nonatomic, strong) JSContext *activeContext;
@property(nonatomic) BOOL runFailed;
@property(nonatomic) NSUInteger runFetchStarted;
@property(nonatomic) NSUInteger runFetchFinished;
@property(nonatomic) NSUInteger runHTTPSuccessCount;
+ (instancetype)shared;
- (void)captureRequest:(NSURLRequest *)request;
- (void)startForWelfareEntry;
- (void)startForWelfareEntry:(NSString *)source;
- (void)presentMessage:(NSString *)message title:(NSString *)title;
- (void)presentMessage:(NSString *)message title:(NSString *)title completion:(dispatch_block_t)completion;
@end

@implementation QDRAutoRunner

+ (instancetype)shared {
    static QDRAutoRunner *runner;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        runner = [QDRAutoRunner new];
        runner.queue = dispatch_queue_create("com.swiftss.qdreaderautocheckin.js", DISPATCH_QUEUE_SERIAL);
    });
    return runner;
}

- (NSString *)scriptPath {
    Dl_info info = {0};
    NSString *dylib = nil;
    // A function address is reliably mapped to this Mach-O image.  The old
    // global NSString address can be coalesced and made dladdr return nothing.
    if (dladdr((const void *)&QDRLog, &info) && info.dli_fname) {
        dylib = [NSString stringWithUTF8String:info.dli_fname];
    }
    if (!dylib.length) {
        for (uint32_t index = 0; index < _dyld_image_count(); index++) {
            const char *name = _dyld_get_image_name(index);
            if (!name) continue;
            NSString *image = [NSString stringWithUTF8String:name];
            if ([image.lastPathComponent isEqualToString:@"QDReaderAutoCheckin.dylib"]) {
                dylib = image;
                break;
            }
        }
    }
    if (dylib.length) {
        // RootHide maps Library/MobileSubstrate/DynamicLibraries to
        // <random .jbroot>/usr/lib/TweakInject.  Keep the resource beside the
        // dylib so the same transformation always applies to both files.
        NSString *adjacent = [[dylib stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent:@"QDReaderAutoCheckin/qdreader.js"];
        BOOL adjacentExists = [[NSFileManager defaultManager] fileExistsAtPath:adjacent];
        QDRLog(@"script resolve dylib=%@ adjacent=%@ exists=%d", dylib, adjacent, adjacentExists);
        if (adjacentExists) return adjacent;

        // Compatibility with older rootful/rootless layouts.
        NSString *marker = @"/Library/MobileSubstrate/DynamicLibraries/";
        NSRange range = [dylib rangeOfString:marker options:NSBackwardsSearch];
        NSString *library = range.location != NSNotFound
            ? [[dylib substringToIndex:range.location] stringByAppendingPathComponent:@"Library"]
            : [[[dylib stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSString *candidate = [library stringByAppendingPathComponent:@"Application Support/QDReaderAutoCheckin/qdreader.js"];
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:candidate];
        QDRLog(@"script legacy candidate=%@ exists=%d", candidate, exists);
        if (exists) return candidate;
    } else {
        QDRLog(@"script resolve: own dylib image not found");
    }
    for (NSString *candidate in @[
        @"/var/jb/Library/Application Support/QDReaderAutoCheckin/qdreader.js",
        @"/Library/Application Support/QDReaderAutoCheckin/qdreader.js"
    ]) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) return candidate;
    }
    return nil;
}

- (NSUserDefaults *)store {
    NSUserDefaults *store = [[NSUserDefaults alloc] initWithSuiteName:QDRPrefsSuite];
    for (NSString *key in @[
        @"QDREADER_ADV_JOB_ENABLE",
        @"QDREADER_EXTRA_ADV_JOB_ENABLE",
        @"QDREADER_LOTTERY_ENABLE",
        @"QDREADER_WEEKLY_EXCHANGE_ENABLE",
        @"QDREADER_CHAPTER_CARD_ENABLE",
        @"QDREADER_MESSAGE_BOX_ENABLE"
    ]) {
        if ([store objectForKey:key] == nil) [store setObject:@"true" forKey:key];
    }
    [store synchronize];
    return store;
}

- (void)captureRequest:(NSURLRequest *)request {
    if (![request.URL.absoluteString.lowercaseString containsString:@"getlogininfo"]) return;
    NSDictionary *headers = request.allHTTPHeaderFields ?: @{};
    NSString *cookie = headers[@"Cookie"] ?: headers[@"cookie"];
    if (cookie.length == 0) { QDRLog(@"getlogininfo observed but Cookie header is empty"); return; }

    // Run upstream once in rewrite/capture mode. It owns the exact QDHeader uid
    // parsing and QDREADER_COOKIE JSON-map format.
    NSDictionary *requestObject = @{
        @"url": request.URL.absoluteString ?: @"",
        @"method": request.HTTPMethod ?: @"GET",
        @"headers": headers,
        @"body": request.HTTPBody ? [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding] ?: @"" : @""
    };
    dispatch_async(self.queue, ^{
        [self evaluateWithRequest:requestObject completion:nil];
    });
}

- (void)startForWelfareEntry {
    [self startForWelfareEntry:@"legacy-entry"];
}

- (NSString *)todayKey {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd";
    return [formatter stringFromDate:NSDate.date];
}

- (void)startForWelfareEntry:(NSString *)source {
    dispatch_async(self.queue, ^{
        if ([[[self store] stringForKey:QDRLastCompletedKey] isEqualToString:[self todayKey]]) {
            QDRLog(@"skip: all tasks already completed today");
            [self presentMessage:@"今日任务已经执行完成，无需重复运行" title:@"起点自动签到"];
            return;
        }
        if (self.running) { QDRLog(@"skip: task is already running"); return; }
        [self presentMessage:@"已检测到福利中心，开始执行全部任务。离开本页不会中断。" title:@"任务已开始"];
        [self seedCookieFromStorageIfNeeded];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), self.queue, ^{ [self beginRunIfIdle]; });
    });
}

- (void)seedCookieFromStorageIfNeeded {
    if ([[self store] stringForKey:@"QDREADER_COOKIE"].length) return;
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSHTTPCookie *cookie in NSHTTPCookieStorage.sharedHTTPCookieStorage.cookies) {
        NSString *domain = cookie.domain.lowercaseString;
        if ([domain containsString:@"qidian"] || [domain containsString:@"qdmm"] || [domain containsString:@"yuewen"]) {
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", cookie.name, cookie.value]];
        }
    }
    if (!pairs.count) { QDRLog(@"cookie fallback found no Qidian cookies"); return; }
    NSString *cookieHeader = [pairs componentsJoinedByString:@"; "];

    Class helperClass = NSClassFromString(@"QDUserHelper");
    id userId = nil;
    if ([helperClass respondsToSelector:@selector(currentUserId)]) userId = ((id (*)(id, SEL))objc_msgSend)(helperClass, @selector(currentUserId));
    if (!userId) {
        Class commonClass = NSClassFromString(@"_TtC7QDLogin11LoginCommon");
        if ([commonClass respondsToSelector:@selector(currentUserId)]) userId = ((id (*)(id, SEL))objc_msgSend)(commonClass, @selector(currentUserId));
    }
    NSString *uid = [[userId description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSString *headerKey = @"QDHeader";
    NSString *headerValue = nil;
    Class headerClass = NSClassFromString(@"QDHeaderService");
    id headerService = headerClass ? [headerClass new] : nil;
    if ([headerService respondsToSelector:@selector(getQDHeaderKey)]) headerKey = ((id (*)(id, SEL))objc_msgSend)(headerService, @selector(getQDHeaderKey)) ?: headerKey;
    if ([headerService respondsToSelector:@selector(getQDHeaderValue)]) headerValue = ((id (*)(id, SEL))objc_msgSend)(headerService, @selector(getQDHeaderValue));

    if (uid.length && ![uid isEqualToString:@"0"] && ![uid isEqualToString:@"(null)"]) {
        NSData *mapData = [NSJSONSerialization dataWithJSONObject:@{uid: cookieHeader} options:0 error:nil];
        NSString *map = [[NSString alloc] initWithData:mapData encoding:NSUTF8StringEncoding];
        if (map.length) {
            [[self store] setObject:map forKey:@"QDREADER_COOKIE"];
            [[self store] synchronize];
        }
    }

    NSMutableURLRequest *synthetic = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://druidv6.if.qidian.com/argus/api/v1/user/getlogininfo"]];
    [synthetic setValue:cookieHeader forHTTPHeaderField:@"Cookie"];
    if (headerValue.length) {
        [synthetic setValue:headerValue forHTTPHeaderField:headerKey ?: @"QDHeader"];
        [self captureRequest:synthetic];
    }
}

- (void)beginRunIfIdle {
    if (self.running) { QDRLog(@"begin ignored: already running"); return; }
    NSString *cookies = [[self store] stringForKey:@"QDREADER_COOKIE"];
    if (cookies.length == 0) {
        QDRLog(@"begin blocked: QDREADER_COOKIE unavailable");
        [self presentMessage:@"未取得登录 Cookie。请确认起点账号已登录，再重新进入福利中心，并把日志发给我。" title:@"任务未启动"];
        return;
    }
    self.running = YES;
    self.runFailed = NO;
    self.runFetchStarted = 0;
    self.runFetchFinished = 0;
    self.runHTTPSuccessCount = 0;
    QDRLog(@"script run started; script=%@", [self scriptPath] ?: @"<missing>");
    self.pendingNotice = nil;
    [self evaluateWithRequest:nil completion:^{
        self.running = NO;
        BOOL failureText = [self.pendingNotice containsString:@"失败"] || [self.pendingNotice containsString:@"异常"] ||
                           [self.pendingNotice containsString:@"错误"] || [self.pendingNotice containsString:@"未完成"];
        BOOL requestsComplete = self.runFetchStarted > 0 && self.runFetchFinished == self.runFetchStarted;
        BOOL verified = !self.runFailed && !failureText && requestsComplete && self.runHTTPSuccessCount > 0;
        if (verified) {
            [[self store] setObject:[self todayKey] forKey:QDRLastCompletedKey];
            [[self store] synchronize];
            QDRLog(@"script run verified; requests=%lu success=%lu; daily completion recorded",
                   (unsigned long)self.runFetchStarted, (unsigned long)self.runHTTPSuccessCount);
        } else {
            QDRLog(@"script run unverified failed=%d requests=%lu finished=%lu success=%lu notice=%@",
                   self.runFailed, (unsigned long)self.runFetchStarted,
                   (unsigned long)self.runFetchFinished, (unsigned long)self.runHTTPSuccessCount,
                   self.pendingNotice ?: @"<none>");
        }
        NSString *message = nil;
        if (verified) message = self.pendingNotice.length ? self.pendingNotice : @"签到任务已完成并通过请求校验。";
        else if (self.runFailed) message = self.pendingNotice.length ? self.pendingNotice : @"签到脚本未成功执行，请导出日志排查。";
        else if (self.runFetchStarted == 0) message = @"脚本已结束，但未发起任何签到请求，本次不计为成功。";
        else if (!requestsComplete) message = @"脚本在网络请求完成前提前结束，本次不计为成功。";
        else if (self.runHTTPSuccessCount == 0) message = @"签到请求均未获得成功响应，请稍后重试。";
        else message = @"脚本未返回可验证的执行结果，本次不计为成功。";
        [self presentCompletion:message];
    }];
}

- (void)presentMessage:(NSString *)message title:(NSString *)title {
    [self presentMessage:message title:title completion:nil];
}

- (void)presentMessage:(NSString *)message title:(NSString *)title completion:(dispatch_block_t)completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *app = UIApplication.sharedApplication;
        UIWindow *window = nil;
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *item in ((UIWindowScene *)scene).windows) if (item.isKeyWindow) { window = item; break; }
        }
        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).visibleViewController;
        if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
        if (!vc) { if (completion) completion(); return; }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { if (completion) completion(); }]];
        [vc presentViewController:alert animated:YES completion:nil];
        // Only the initial welfare-entry hint auto-dismisses.  Completion,
        // failure, cookie and already-completed notices require confirmation.
        BOOL transient = [title isEqualToString:@"\u4efb\u52a1\u5df2\u5f00\u59cb"];
        if (transient) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (alert.presentingViewController) [alert dismissViewControllerAnimated:YES completion:completion];
        });
    });
}

- (void)presentCompletion:(NSString *)message {
    [self presentMessage:message title:@"全部任务执行结束"];
}

- (void)evaluateWithRequest:(NSDictionary *)requestObject completion:(dispatch_block_t)completion {
    NSError *error = nil;
    NSString *resolvedScriptPath = [self scriptPath];
    NSString *source = resolvedScriptPath.length ? [NSString stringWithContentsOfFile:resolvedScriptPath encoding:NSUTF8StringEncoding error:&error] : nil;
    if (source.length == 0) {
        self.runFailed = YES;
        self.pendingNotice = @"签到脚本文件未找到或读取失败，请重新安装 RootHide 版插件。";
        QDRLog(@"script load failed path=%@ error=%@", resolvedScriptPath ?: @"<missing>", error);
        if (completion) completion();
        return;
    }

    JSContext *context = [JSContext new];
    self.activeContext = context;
    __weak JSContext *weakContext = context;
    __block BOOL finished = NO;
    __weak typeof(self) weakSelf = self;
    context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        QDRLog(@"JavaScript exception: %@", exception.toString);
        weakSelf.runFailed = YES;
        weakSelf.pendingNotice = [NSString stringWithFormat:@"脚本异常：%@", exception.toString ?: @"未知错误"];
        if (!finished) { finished = YES; weakSelf.activeContext = nil; if (completion) completion(); }
    };

    context[@"__nativePrefGet"] = ^NSString *(NSString *key) {
        id value = [[weakSelf store] objectForKey:key];
        return [value isKindOfClass:NSString.class] ? value : ([value description] ?: nil);
    };
    context[@"__nativePrefSet"] = ^BOOL(NSString *value, NSString *key) {
        if (!key.length) return NO;
        if (value) [[weakSelf store] setObject:value forKey:key]; else [[weakSelf store] removeObjectForKey:key];
        return [[weakSelf store] synchronize];
    };
    context[@"__nativeResolveURL"] = ^NSString *(NSString *input, NSString *base) {
        if (![input isKindOfClass:NSString.class]) return @"{}";
        NSURL *baseURL = [base isKindOfClass:NSString.class] && base.length ? QDRCreateURL(base, nil) : nil;
        NSURL *resolvedURL = QDRCreateURL(input, baseURL).absoluteURL;
        NSURLComponents *components = resolvedURL ? [NSURLComponents componentsWithURL:resolvedURL resolvingAgainstBaseURL:YES] : nil;
        if (!components.URL.absoluteString.length) return @"{}";
        NSString *scheme = components.scheme ?: @"";
        NSString *hostname = components.host ?: @"";
        NSString *port = components.port.stringValue ?: @"";
        NSString *host = port.length ? [NSString stringWithFormat:@"%@:%@", hostname, port] : hostname;
        NSString *origin = (scheme.length && host.length) ? [NSString stringWithFormat:@"%@://%@", scheme, host] : @"null";
        NSDictionary *result = @{
            @"href": components.URL.absoluteString ?: @"",
            @"origin": origin,
            @"protocol": scheme.length ? [scheme stringByAppendingString:@":"] : @"",
            @"username": components.user ?: @"",
            @"password": components.password ?: @"",
            @"host": host,
            @"hostname": hostname,
            @"port": port,
            @"pathname": components.percentEncodedPath.length ? components.percentEncodedPath : @"/",
            @"search": components.percentEncodedQuery.length ? [@"?" stringByAppendingString:components.percentEncodedQuery] : @"",
            @"hash": components.percentEncodedFragment.length ? [@"#" stringByAppendingString:components.percentEncodedFragment] : @""
        };
        NSData *resultData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        return [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding] ?: @"{}";
    };
    context[@"__nativeFetch"] = ^(NSString *json, NSNumber *callbackId) {
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *options = [parsed isKindOfClass:NSDictionary.class] ? parsed : @{};
        NSString *urlString = [parsed isKindOfClass:NSString.class] ? parsed : options[@"url"];
        NSURL *url = QDRCreateURL(urlString ?: @"", nil);
        if (!url) {
            weakSelf.runFailed = YES;
            weakSelf.pendingNotice = @"脚本生成了无效的签到请求地址。";
            QDRLog(@"request rejected: invalid URL");
            return;
        }
        if (!requestObject) weakSelf.runFetchStarted += 1;
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = options[@"method"] ?: @"GET";
        request.timeoutInterval = 30;
        NSDictionary *headers = options[@"headers"];
        if ([headers isKindOfClass:NSDictionary.class]) for (id key in headers) [request setValue:[headers[key] description] forHTTPHeaderField:[key description]];
        id body = options[@"body"];
        if ([body isKindOfClass:NSString.class]) request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
        [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *bodyData, NSURLResponse *response, NSError *networkError) {
            dispatch_async(weakSelf.queue, ^{
                NSMutableDictionary *result = [NSMutableDictionary dictionary];
                NSInteger statusCode = 0;
                if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                    NSHTTPURLResponse *http = (id)response;
                    statusCode = http.statusCode;
                    result[@"statusCode"] = @(http.statusCode);
                    result[@"headers"] = http.allHeaderFields ?: @{};
                }
                if (!requestObject) {
                    weakSelf.runFetchFinished += 1;
                    if (!networkError && statusCode >= 200 && statusCode < 300) weakSelf.runHTTPSuccessCount += 1;
                }
                result[@"body"] = bodyData ? [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"" : @"";
                result[@"error"] = networkError.localizedDescription ?: @"";
                if (networkError || statusCode < 200 || statusCode >= 300) QDRLog(@"request failed status=%ld error=%@ response=%@", (long)statusCode, networkError.localizedDescription ?: @"<none>", QDRRedactedExcerpt(bodyData));
                NSData *resultData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                NSString *resultJSON = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding] ?: @"{}";
                [weakContext[@"__qdFetchComplete"] callWithArguments:@[callbackId, resultJSON, @(networkError != nil)]];
            });
        }] resume];
    };
    context[@"__nativeDelay"] = ^(NSNumber *callbackId, NSNumber *milliseconds) {
        double delay = MAX(0, milliseconds.doubleValue) / 1000.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), weakSelf.queue, ^{
            [weakContext[@"__qdTimerFire"] callWithArguments:@[callbackId]];
        });
    };
    context[@"__nativeNotify"] = ^(id title, id subtitle, id body) {
        NSMutableArray *parts = [NSMutableArray array];
        for (id value in @[title ?: @"", subtitle ?: @"", body ?: @""]) {
            NSString *text = [value isKindOfClass:NSString.class] ? value : [value description];
            if (text.length) [parts addObject:text];
        }
        weakSelf.pendingNotice = [parts componentsJoinedByString:@"\n"];
    };
    context[@"__nativeDone"] = ^{
        if (!finished) { finished = YES; weakSelf.activeContext = nil; if (completion) completion(); }
    };

    NSString *bootstrap =
    @"var __qdCallbacks={},__qdTimers={},__qdSeq=1;"
    "if(typeof URLSearchParams==='undefined'){"
      "var URLSearchParams=function(init){this._p=[];if(!init)return;"
        "if(typeof init==='string'){var s=init.charAt(0)==='?'?init.slice(1):init;if(s)for(var a=s.split('&'),i=0;i<a.length;i++){var x=a[i].split('='),k=decodeURIComponent((x.shift()||'').replace(/\\+/g,' ')),v=decodeURIComponent(x.join('=').replace(/\\+/g,' '));this.append(k,v)}}"
        "else if(Array.isArray(init)){for(var j=0;j<init.length;j++)this.append(init[j][0],init[j][1])}"
        "else{for(var key in init)if(Object.prototype.hasOwnProperty.call(init,key))this.append(key,init[key])}};"
      "URLSearchParams.prototype.append=function(k,v){this._p.push([String(k),String(v)])};"
      "URLSearchParams.prototype.set=function(k,v){this.delete(k);this.append(k,v)};"
      "URLSearchParams.prototype.get=function(k){k=String(k);for(var i=0;i<this._p.length;i++)if(this._p[i][0]===k)return this._p[i][1];return null};"
      "URLSearchParams.prototype.getAll=function(k){k=String(k);var r=[];for(var i=0;i<this._p.length;i++)if(this._p[i][0]===k)r.push(this._p[i][1]);return r};"
      "URLSearchParams.prototype.has=function(k){return this.get(k)!==null};"
      "URLSearchParams.prototype.delete=function(k){k=String(k);this._p=this._p.filter(function(x){return x[0]!==k})};"
      "URLSearchParams.prototype.forEach=function(f,t){for(var i=0;i<this._p.length;i++)f.call(t,this._p[i][1],this._p[i][0],this)};"
      "URLSearchParams.prototype.toString=function(){return this._p.map(function(x){return encodeURIComponent(x[0]).replace(/%20/g,'+')+'='+encodeURIComponent(x[1]).replace(/%20/g,'+')}).join('&')};"
    "}"
    "URL=function(input,base){"
      "if(!(this instanceof URL))throw new TypeError('URL must be constructed');"
      "var raw=__nativeResolveURL(String(input),base===undefined?'':String(base)),parts=JSON.parse(raw||'{}');"
      "if(!parts.href)throw new TypeError('Invalid URL');"
      "for(var key in parts)if(Object.prototype.hasOwnProperty.call(parts,key))this[key]=parts[key];"
      "this.searchParams=new URLSearchParams(this.search);"
    "};"
    "URL.prototype.toString=function(){return this.href};"
    "URL.prototype.toJSON=function(){return this.href};"
    "URL.canParse=function(input,base){try{new URL(input,base);return true}catch(e){return false}};"
    "URL.parse=function(input,base){try{return new URL(input,base)}catch(e){return null}};"
    "var $prefs={valueForKey:function(k){return __nativePrefGet(k)},setValueForKey:function(v,k){return __nativePrefSet(v,k)}};"
    "var $task={fetch:function(o){if(typeof o==='string')o={url:o};return new Promise(function(resolve,reject){var i=__qdSeq++;__qdCallbacks[i]=[resolve,reject];__nativeFetch(JSON.stringify(o),i)})}};"
    "function __qdFetchComplete(i,j,bad){var c=__qdCallbacks[i];delete __qdCallbacks[i];if(!c)return;var r=JSON.parse(j);bad?c[1](r.error):c[0](r)}"
    "function setTimeout(f,ms){var i=__qdSeq++;__qdTimers[i]=f;__nativeDelay(i,ms||0);return i}"
    "function clearTimeout(i){delete __qdTimers[i]} function __qdTimerFire(i){var f=__qdTimers[i];delete __qdTimers[i];if(f)f()}"
    "var $notify=function(a,b,c){__nativeNotify(a,b,c)};var $notification={post:$notify};"
    "var $done=function(){__nativeDone()};var console={log:function(){}};";
    [context evaluateScript:bootstrap];
    if (requestObject) context[@"$request"] = requestObject;
    [context evaluateScript:source withSourceURL:[NSURL fileURLWithPath:[self scriptPath]]];
}

@end

static void QDRObserveTask(NSURLSessionTask *task) {
    NSURLRequest *request = task.originalRequest ?: task.currentRequest;
    if ([request.URL.absoluteString.lowercaseString containsString:@"getlogininfo"]) {
        [[QDRAutoRunner shared] captureRequest:request];
    }
}

%hook NSURLSessionTask
- (void)resume {
    QDRObserveTask(self);
    %orig;
}
%end

%hook _TtC16QDReaderAppStore37QDNewUserWelfareFlutterViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[QDRAutoRunner shared] startForWelfareEntry:@"new-user-welfare-vc"];
}
%end

%hook _TtC16QDReaderAppStore32QDBookStoreFlutterViewController
- (id)initWithEntryPoint:(id)entryPoint argsMap:(id)args libraryURI:(id)libraryURI initialRoute:(id)route {
    id instance = %orig;
    if ([route isKindOfClass:NSString.class] && [route containsString:@"welfareCenter"]) {
        objc_setAssociatedObject(instance, @selector(startForWelfareEntry), @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return instance;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if ([objc_getAssociatedObject(self, @selector(startForWelfareEntry)) boolValue]) {
        [[QDRAutoRunner shared] startForWelfareEntry:@"bookstore-initial-route"];
    }
}
%end

%hook QDRouter
+ (BOOL)openURL:(id)url {
    BOOL welfare = [[url description].lowercaseString containsString:@"welfarecenter"];
    BOOL result = %orig;
    if (welfare) [[QDRAutoRunner shared] startForWelfareEntry:@"qdrouter-openurl"];
    return result;
}
%end

%hook NSObject
- (BOOL)qd_handleActionUrl:(id)url {
    BOOL welfare = [[url description].lowercaseString containsString:@"welfarecenter"];
    BOOL result = %orig;
    if (welfare) [[QDRAutoRunner shared] startForWelfareEntry:@"action-url"];
    return result;
}
%end

// Preserve Qidian's splash lifecycle and activate its own skip/close path.
// Returning early from load/show leaves the launch coordinator waiting forever.
%hook QDSplashView
- (void)addSkipButton {
    %orig;
    QDRScheduleSplashSkip(0);
}
%end

%hook _TtC16QDReaderAppStore24QDCommercialSplashHelper
- (BOOL)shouldShowCommercialSplashAd {
    // This predicate is the helper's supported "no ad this launch" path.
    // Keep the launch coordinator alive and prevent the native QDSplashView
    // (including cached first-party book promotions) from being created.
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setThisTimeLaunchNotShowCommercialSplash:), YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setThisTimeLaunchIsCommercialSplash:), NO);
    return NO;
}

- (BOOL)showCommercialSplashScreen {
    // A cached commercial splash can reach this second predicate without
    // loading from the network. Report "not shown" so the caller continues
    // the normal app launch flow.
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setThisTimeLaunchNotShowCommercialSplash:), YES);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setThisTimeLaunchIsCommercialSplash:), NO);
    return NO;
}

- (void)showSplashAd {
    %orig;
    QDRScheduleSplashSkip(0);
}
%end

%hook _TtC16QDReaderAppStore16QDPangleSplashAd
- (void)handlerCountDown {
    ((void (*)(id, SEL))objc_msgSend)(self, @selector(clickSkipButton));
}
%end

%hook _TtC16QDReaderAppStore13QDGDTSplashAd
- (void)showAd {
    %orig;
    QDRScheduleSplashSkip(0);
}

static BOOL QDRReadSwiftBoolIvar(id object, const char *name, BOOL *value, ptrdiff_t *resolvedOffset) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return NO;
    ptrdiff_t offset = ivar_getOffset(ivar);
    if (resolvedOffset) *resolvedOffset = offset;
    if (value) *value = *((uint8_t *)(__bridge void *)object + offset) != 0;
    return YES;
}

static ptrdiff_t QDRIvarOffsetContaining(id object, NSString *fragment) {
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(object), &count);
    ptrdiff_t offset = -1;
    for (unsigned int index = 0; index < count; index++) {
        NSString *name = [NSString stringWithUTF8String:ivar_getName(ivars[index]) ?: ""];
        if ([name containsString:fragment]) {
            offset = ivar_getOffset(ivars[index]);
            break;
        }
    }
    free(ivars);
    return offset;
}

static void QDRInvokeNativeShelfFold(id controller, id topAdView, NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!controller || !topAdView || ![(UIViewController *)controller viewIfLoaded].window) return;
        BOOL expanded = NO;
        ptrdiff_t stateOffset = -1;
        if (!QDRReadSwiftBoolIvar(controller, "isBgOpen", &expanded, &stateOffset)) {
            QDRLog(@"bookshelf native fold unavailable: isBgOpen ivar missing");
            return;
        }
        if (!expanded) {
            QDRLog(@"bookshelf native fold already collapsed stateOffset=0x%tx", stateOffset);
            return;
        }
        ptrdiff_t handlerOffset = QDRIvarOffsetContaining(topAdView, @"foldAdBannerHandler");
        if (handlerOffset >= 0) {
            uintptr_t *closure = (uintptr_t *)((uint8_t *)(__bridge void *)topAdView + handlerOffset);
            void *function = (void *)closure[0];
            void *context = (void *)closure[1];
            if (!function) {
                if (attempt < 20) QDRInvokeNativeShelfFold(controller, topAdView, attempt + 1);
                else QDRLog(@"bookshelf native fold unresolved handler=nil offset=0x%tx", handlerOffset);
                return;
            }
            if (!objc_getAssociatedObject(topAdView, QDRShelfNativeFoldKey)) {
                objc_setAssociatedObject(topAdView, QDRShelfNativeFoldKey, @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                QDRInvokeSwiftVoidClosure(function, context);
                QDRLog(@"bookshelf native Swift fold handler invoked stateOffset=0x%tx handlerOffset=0x%tx",
                       stateOffset, handlerOffset);
            }
        } else {
            QDRLog(@"bookshelf native fold unresolved handler ivar missing");
        }
    });
}
%end

%group QDRShelfPromotionHooks

%hook QDRShelfViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    id topAdView = [self respondsToSelector:@selector(topAdView)]
        ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(topAdView)) : nil;
    QDRInvokeNativeShelfFold(self, topAdView, 0);
}
- (void)setTopAdView:(id)view {
    %orig(view);
    QDRInvokeNativeShelfFold(self, view, 0);
}
%end

%end

%ctor {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    if ([bundle isEqualToString:QDRTargetBundle] || [bundle isEqualToString:QDREnterpriseBundle]) {
        QDRLog(@"loaded version=1.4.2 bundle=%@", bundle);
        %init;
        Class shelfVC = objc_getClass("_TtC16QDReaderAppStore25QDBookShelfViewController");
        if (shelfVC) {
            %init(QDRShelfPromotionHooks,
                  QDRShelfViewController = shelfVC);
        } else {
            QDRLog(@"bookshelf collapsed-state hook unavailable vc=0");
        }
    }
}
