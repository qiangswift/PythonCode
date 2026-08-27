# Zhixing Update Blocker

[![Build Zhixing Update Blocker](https://github.com/swiftss/PythonCode/actions/workflows/zhixing-update-blocker.yml/badge.svg)](https://github.com/swiftss/PythonCode/actions/workflows/zhixing-update-blocker.yml)

针对智行火车票 `10.19.2`（Bundle ID：`cn.suanya.zhixingHC`）的越狱插件，屏蔽版本更新弹窗、首页营销浮层与启动广告。

## 实现范围

- 屏蔽 `ZTAppUpdateVC` 与 `ZTAppGuideUpdateViewController` 的展示。
- 同时拦截二进制中定位到的 6 个版本更新 UI 入口。
- 屏蔽 `ZTMarketHomePopViewController` 首页营销浮层与酒店首页营销浮层。
- 跳过 `CTAdSdkSplashViewManager` 的广告展示，并复现正常关闭时的 `actionBlock(3)`，让启动状态机继续执行。

- 不修改版本号、不伪造接口数据，也不拦截普通 `UIAlertController`，避免影响登录、支付等其他提示。

## 编译

需要 macOS/Linux 上已配置好的 Theos 与 iOS SDK：

```sh
cd iOS17_dylib/ZhixingUpdateBlocker
make clean package FINALPACKAGE=1
```

生成的 deb 位于 `packages/`。安装后执行：

```sh
killall Zhixing
```

支持 arm64/arm64e，最低部署目标 iOS 15。默认以 Theos 当前环境的打包方案生成；rootless 越狱可按所用 Theos/越狱环境增加 `THEOS_PACKAGE_SCHEME=rootless` 后重新打包。
