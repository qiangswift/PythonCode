# China Mobile Splash Ad Blocker

[![Build China Mobile Splash Ad Blocker](https://github.com/swiftss/PythonCode/actions/workflows/china-mobile-splash-ad-blocker.yml/badge.svg)](https://github.com/swiftss/PythonCode/actions/workflows/china-mobile-splash-ad-blocker.yml)

适用于中国移动 `12.5.2`，Bundle ID：`cn.10086.app`。

插件仅令 `-[CMStartViewController isNeedSkipStartAd]` 返回 `YES`，由 App 原生的 `skipStartViewAndEnterMainPage` 流程完成页面切换，不拦截广告 SDK、网络请求或全局视图方法。

## 编译

```sh
cd iOS17_dylib/ChinaMobileSplashAdBlocker
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```
