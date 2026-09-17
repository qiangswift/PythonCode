#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static NSTimeInterval FMClaimUntil = 0;
static BOOL FMClaimActive(void) { return [NSDate date].timeIntervalSince1970 <= FMClaimUntil; }
static void FMLog(NSString *line);
static NSString *FMSafeValue(id value);
static NSDictionary *FMObjectFields(id object);

@interface FMWebProbe : NSObject <WKScriptMessageHandler>
@end

@implementation FMWebProbe
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)controller;
    NSDictionary *body = [message.body isKindOfClass:NSDictionary.class] ? message.body : nil;
    if (!body) return;
    NSString *kind = FMSafeValue(body[@"kind"]);
    NSString *api = FMSafeValue(body[@"api"]);
    if ([kind isEqualToString:@"page"]) {
        FMLog([NSString stringWithFormat:@"web page host=%@", api ?: @"unknown"]);
        return;
    }
    if ([kind isEqualToString:@"ui-error"] && [api isEqualToString:@"web:claim-failed"]) {
        FMLog(@"claim UI alert source=WebView");
        return;
    }
    if (![kind isEqualToString:@"request"] && ![kind isEqualToString:@"response"] &&
        ![kind isEqualToString:@"bridge"] && ![kind isEqualToString:@"bridge-result"]) return;
    if (!api || !([api hasPrefix:@"mtop."] || [api hasPrefix:@"web:"] || [api hasPrefix:@"bridge:"])) return;
    if ([kind isEqualToString:@"request"] || [kind isEqualToString:@"bridge"]) {
        FMLog([NSString stringWithFormat:@"%@ api=%@", kind, api]);
    } else {
        FMLog([NSString stringWithFormat:@"%@ api=%@ status=%@ fields=%@",
               kind, api, FMSafeValue(body[@"status"]) ?: @"?", FMObjectFields(body[@"fields"])]);
    }
}
@end

static NSString *FMLogPath(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [documents stringByAppendingPathComponent:@"FleamarketClaimLog.log"];
}

static void FMLog(NSString *line) {
    @synchronized (NSFileManager.defaultManager) {
        NSString *path = FMLogPath();
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
        if ([attributes[NSFileSize] unsignedLongLongValue] >= 1024 * 1024) return;
        static NSDateFormatter *formatter;
        if (!formatter) {
            formatter = [NSDateFormatter new];
            formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS ZZZZ";
            formatter.timeZone = NSTimeZone.localTimeZone;
        }
        NSString *entry = [NSString stringWithFormat:@"%@: %@\n", [formatter stringFromDate:NSDate.date], line];
        NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
        if (!attributes) [data writeToFile:path atomically:YES];
        else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle closeFile];
        }
    }
}

static BOOL FMIsClaimURL(NSURL *url) {
    NSString *value = url.absoluteString.lowercaseString ?: @"";
    return [value containsString:@"mtop.taobao.idle.oliver.batch.issue"] ||
           [value containsString:@"idle.oliver.batch.issue"];
}

static NSString *FMSafeValue(id value) {
    if (![value isKindOfClass:NSString.class] && ![value isKindOfClass:NSNumber.class]) return nil;
    NSString *text = [value description];
    return text.length > 180 ? [[text substringToIndex:180] stringByAppendingString:@"…"] : text;
}

static NSDictionary *FMObjectFields(id object) {
    if (!object || object == [NSNull null]) return @{};
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    NSDictionary *dictionary = [object isKindOfClass:NSDictionary.class] ? object : nil;
    for (NSString *key in @[ @"ret", @"code", @"errorCode", @"errorMsg", @"msg", @"message", @"success", @"resultCode" ]) {
        id value = dictionary[key];
        if (!dictionary) {
            @try { value = [object valueForKey:key]; } @catch (NSException *exception) { value = nil; }
        }
        if ([value isKindOfClass:NSArray.class]) {
            NSMutableArray *items = [NSMutableArray array];
            for (id item in (NSArray *)value) {
                NSString *safe = FMSafeValue(item);
                if (safe && items.count < 4) [items addObject:safe];
            }
            if (items.count) fields[key] = items;
        } else {
            NSString *safe = FMSafeValue(value);
            if (safe) fields[key] = safe;
        }
    }
    return fields;
}

static id FMProperty(id object, NSString *key) {
    if (!object || object == NSNull.null) return nil;
    if ([object isKindOfClass:NSDictionary.class]) return ((NSDictionary *)object)[key];
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}

static NSDictionary *FMResponseSummary(id object) {
    NSMutableDictionary *summary = [FMObjectFields(object) mutableCopy];
    for (NSString *key in @[ @"data", @"result", @"error", @"model" ]) {
        id nested = FMProperty(object, key);
        if (!nested || nested == NSNull.null) continue;
        NSDictionary *fields = FMObjectFields(nested);
        if (fields.count) summary[key] = fields;
        else if (![nested isKindOfClass:NSDictionary.class] && ![nested isKindOfClass:NSArray.class])
            summary[[key stringByAppendingString:@".class"]] = NSStringFromClass([nested class]);
    }
    return summary;
}

static NSString *FMWebScript(void) {
    return @"(function(){if(window.__fmClaimProbe)return;window.__fmClaimProbe=1;"
    @"function api(u){try{var x=new URL(String(u||''),location.href);if(!/^https?:$/.test(x.protocol))return null;"
    @"var m=(x.pathname+x.search).toLowerCase().match(/mtop\\.[a-z0-9_.]+/);if(m)return m[0];"
    @"var p=x.pathname.split('/').filter(Boolean).slice(0,4).map(function(s){return /^[a-z0-9._-]{1,24}$/i.test(s)&&!/^\\d+$/.test(s)?s:':id'}).join('/');return 'web:'+x.hostname+'/'+p}catch(e){return null}}"
    @"function send(x){try{window.webkit.messageHandlers.fmClaimProbe.postMessage(x)}catch(e){}}"
    @"send({kind:'page',api:location.hostname||'local'});"
    @"function fields(t){try{var o=JSON.parse(t);if(!o||typeof o!=='object')return {};"
    @"var r={};['ret','code','errorCode','msg','message','success'].forEach(function(k){"
    @"var v=o[k];if(typeof v==='string'||typeof v==='number'||typeof v==='boolean')r[k]=String(v).slice(0,180);"
    @"else if(k==='ret'&&Array.isArray(v))r[k]=v.filter(function(x){return typeof x==='string'}).slice(0,4).map(function(x){return x.slice(0,180)});});"
    @"return r}catch(e){return {}}}"
    @"function bridge(){try{var w=window.WindVane||window.windvane;if(!w||typeof w.call!=='function'||w.call.__fmProbe)return;"
    @"var old=w.call;function wrapped(){var a=Array.prototype.slice.call(arguments);"
    @"var c=String(a[0]||'').replace(/[^a-z0-9_.-]/gi,'_').slice(0,70),m=String(a[1]||'').replace(/[^a-z0-9_.-]/gi,'_').slice(0,70);"
    @"var label='bridge:'+c+'/'+m;send({kind:'bridge',api:label});"
    @"[3,4].forEach(function(j){if(typeof a[j]==='function'){var cb=a[j];a[j]=function(){"
    @"var d={};try{d=fields(typeof arguments[0]==='string'?arguments[0]:JSON.stringify(arguments[0]))}catch(e){}"
    @"send({kind:'bridge-result',api:label,status:j===3?'success':'failure',fields:d});return cb.apply(this,arguments)}}});"
    @"return old.apply(this,a)}wrapped.__fmProbe=true;w.call=wrapped;send({kind:'bridge',api:'bridge:installed'})}catch(e){}}"
    @"bridge();setInterval(bridge,750);setTimeout(function(){var w=window.WindVane||window.windvane;"
    @"if(!w||typeof w.call!=='function')send({kind:'bridge',api:'bridge:unavailable'})},3000);"
    @"var claimShown=false;function checkClaim(){if(claimShown||!document.body)return;"
    @"if((document.body.innerText||'').indexOf('领取失败，请稍后重试')>=0){claimShown=true;"
    @"send({kind:'ui-error',api:'web:claim-failed'})}}"
    @"new MutationObserver(checkClaim).observe(document,{subtree:true,childList:true,characterData:true});"
    @"setInterval(checkClaim,500);"
    @"var of=window.fetch;if(of)window.fetch=function(i,n){var u=typeof i==='string'?i:(i&&i.url),a=api(u);"
    @"if(a)send({kind:'request',api:a});return of.apply(this,arguments).then(function(r){"
    @"if(a){try{r.clone().text().then(function(t){send({kind:'response',api:a,status:r.status,fields:fields(t)})}).catch(function(){})}catch(e){}}return r})};"
    @"var op=XMLHttpRequest.prototype.open,os=XMLHttpRequest.prototype.send;"
    @"XMLHttpRequest.prototype.open=function(m,u){this.__fmApi=api(u);return op.apply(this,arguments)};"
    @"XMLHttpRequest.prototype.send=function(){var a=this.__fmApi;if(a){send({kind:'request',api:a});"
    @"this.addEventListener('loadend',function(){var t='';try{if(this.responseType===''||this.responseType==='text')t=this.responseText}catch(e){}"
    @"send({kind:'response',api:a,status:this.status,fields:fields(t)})})}return os.apply(this,arguments)}"
    @"})();";
}

static NSDictionary *FMResponseFields(NSData *data) {
    if (!data.length) return @{};
    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
    if (![json isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    // Do not recurse into arbitrary account/profile data. MTOP errors are
    // typically in the top-level envelope, occasionally under data/result.
    NSDictionary *root = json;
    for (NSString *key in @[ @"ret", @"code", @"errorCode", @"msg", @"message", @"success" ]) {
        id value = root[key];
        if ([value isKindOfClass:NSArray.class]) {
            NSMutableArray *items = [NSMutableArray array];
            for (id item in (NSArray *)value) {
                NSString *safe = FMSafeValue(item);
                if (safe && items.count < 4) [items addObject:safe];
            }
            if (items.count) fields[key] = items;
        } else if (FMSafeValue(value)) fields[key] = FMSafeValue(value);
    }
    for (NSString *container in @[ @"data", @"result" ]) {
        NSDictionary *nested = [root[container] isKindOfClass:NSDictionary.class] ? root[container] : nil;
        for (NSString *key in @[ @"code", @"errorCode", @"msg", @"message", @"success" ]) {
            NSString *safe = FMSafeValue(nested[key]);
            if (safe) fields[[NSString stringWithFormat:@"%@.%@", container, key]] = safe;
        }
    }
    return fields;
}

static void FMRecord(NSURL *url, NSData *data, NSURLResponse *response, NSError *error) {
    (void)url;
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
    // Never record full URLs, request bodies, headers, or raw response data.
    FMLog([NSString stringWithFormat:@"claim response status=%ld errorDomain=%@ errorCode=%ld fields=%@",
           (long)status, error.domain ?: @"none", (long)error.code, FMResponseFields(data)]);
}

static void FMDescribeMtopClasses(void) {
    for (NSString *name in @[ @"FMMtopRequestModel", @"FMMtopResponseModel", @"FMNetMtopRequest", @"XSearchSwift.OliverBatchIssueRequest", @"OliverBatchIssueRequest" ]) {
        Class cls = NSClassFromString(name);
        if (!cls) { FMLog([NSString stringWithFormat:@"mtop runtime class=%@ unavailable", name]); continue; }
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        NSMutableArray *selectors = [NSMutableArray array];
        for (unsigned int index = 0; index < count; index++) {
            NSString *selector = NSStringFromSelector(method_getName(methods[index]));
            if (selectors.count < 80) [selectors addObject:selector];
        }
        free(methods);
        FMLog([NSString stringWithFormat:@"mtop runtime class=%@ superclass=%@ selectors=%@",
               name, NSStringFromClass(class_getSuperclass(cls)), selectors]);
    }
}

%hook FMMtopRequestModel
- (void)setApiName:(NSString *)apiName {
    if ([apiName.lowercaseString hasPrefix:@"mtop."]) {
        FMLog([NSString stringWithFormat:@"native mtop api=%@", FMSafeValue(apiName)]);
    }
    if ([apiName.lowercaseString containsString:@"idle.oliver.batch.issue"]) {
        FMClaimUntil = [NSDate date].timeIntervalSince1970 + 90;
        FMLog(@"claim request started channel=FMMtopRequestModel");
    }
    if ([apiName.lowercaseString containsString:@"idle.treasure.hunt.map.init"]) {
        FMClaimUntil = [NSDate date].timeIntervalSince1970 + 60;
        FMLog(@"coin page response window opened");
    }
    %orig;
}
%end

%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    if (configuration) {
        @try {
            WKUserContentController *content = configuration.userContentController;
            static FMWebProbe *probe;
            static dispatch_once_t once;
            dispatch_once(&once, ^{ probe = [FMWebProbe new]; });
            [content addScriptMessageHandler:probe name:@"fmClaimProbe"];
            [content addUserScript:[[WKUserScript alloc] initWithSource:FMWebScript()
                                                      injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                   forMainFrameOnly:NO]];
            FMLog(@"webview probe attached");
        } @catch (NSException *exception) {
            FMLog(@"webview probe attach skipped");
        }
    }
    return %orig;
}
%end

%hook FMMtopResponseModel
- (void)setReturnDO:(id)returnDO {
    if (FMClaimActive()) {
        FMLog([NSString stringWithFormat:@"mtop returnDO class=%@ fields=%@",
               returnDO ? NSStringFromClass([returnDO class]) : @"nil", FMResponseSummary(returnDO)]);
    }
    %orig;
}
- (void)setUserInfo:(id)userInfo {
    if (FMClaimActive()) {
        FMLog([NSString stringWithFormat:@"mtop userInfo class=%@ fields=%@",
               userInfo ? NSStringFromClass([userInfo class]) : @"nil", FMObjectFields(userInfo)]);
    }
    %orig;
}
%end

%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!FMIsClaimURL(request.URL)) return %orig;
    FMLog(@"claim request started channel=NSURLSession/request");
    if (!completionHandler) return %orig;
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        FMRecord(request.URL, data, response, error);
        completionHandler(data, response, error);
    };
    return %orig(request, wrapped);
}
- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (!FMIsClaimURL(url)) return %orig;
    FMLog(@"claim request started channel=NSURLSession/url");
    if (!completionHandler) return %orig;
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *response, NSError *error) {
        FMRecord(url, data, response, error);
        completionHandler(data, response, error);
    };
    return %orig(url, wrapped);
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    if ([text containsString:@"领取失败，请稍后重试"] ||
        [text containsString:@"设备异常，请稍后重试"]) {
        FMLog([NSString stringWithFormat:@"claim UI alert=%@",
               [text containsString:@"设备异常"] ? @"device-abnormal" : @"claim-failed"]);
    }
    %orig;
}
%end

%hook UIApplication
- (void)sendEvent:(UIEvent *)event {
    static NSTimeInterval lastMarker = 0;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (event.type == UIEventTypeTouches && now - lastMarker >= 0.4) {
        for (UITouch *touch in event.allTouches) {
            if (touch.phase == UITouchPhaseEnded) {
                lastMarker = now;
                FMLog(@"touch ended");
                break;
            }
        }
    }
    %orig;
}
%end

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.taobao.fleamarket"]) return;
    FMLog(@"loaded version=0.7.0 stage=read-only nested coin response probe");
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        FMDescribeMtopClasses();
    });
}
