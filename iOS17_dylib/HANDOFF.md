# iOS17_dylib 项目交接

最后更新：2026-08-26

## 统一工作目录

所有 iOS、越狱插件、Theos、dylib、deb 和 IPA 分析项目统一位于：

`C:\Users\liqiang\Documents\PythonCode\iOS17_dylib`

当前项目：

- `ChinaMobileSplashAdBlocker`
- `_singlevpn_payload`
- `IFreeTimeAdBlocker`
- `LechengSplashSkip`
- `PortraitLock17`
- `PortraitLockold_reference`
- `QDReaderAutoCheckin`
- `Rails12306AdBlock`
- `ReederPortraitLock`
- `SingleVPN`
- `ZhixingUpdateBlocker`

## Git 仓库关系

父仓库：`swiftss/PythonCode`，分支 `main`，仓库保持私有。

父仓库直接跟踪并已迁移到新路径的项目：

- `ChinaMobileSplashAdBlocker`
- `LechengSplashSkip`
- `SingleVPN`
- `ZhixingUpdateBlocker`

保留独立 Git 历史和远程仓库的项目：

- `PortraitLock17` → `https://github.com/swiftss/PortraitLock17.git`
- `PortraitLockold_reference` → `https://github.com/nanerasingh/PortraitLockold.git`
- `QDReaderAutoCheckin` → `https://github.com/swiftss/QDReaderAutoCheckin.git`
- `Rails12306AdBlock` → `https://github.com/swiftss/Rails12306AdBlock.git`
- `ReederPortraitLock` → `https://github.com/swiftss/ReederPortraitLock.git`

`IFreeTimeAdBlocker` 和 `_singlevpn_payload` 当前是父仓库中的未跟踪本地目录。不要在没有确认内容和发布意图前直接加入 GitHub。

目录迁移提交：`94a24938 Organize iOS tweak projects under iOS17_dylib`。

## GitHub Actions

以下父仓库工作流已更新为 `iOS17_dylib/<ProjectName>/` 路径：

- `china-mobile-splash-ad-blocker.yml`
- `lecheng-splash-skip.yml`
- `singlevpn-build.yml`
- `zhixing-update-blocker.yml`

当前 GitHub-hosted Actions 仍受账户计费/预算锁限制，任务会在 Runner 启动前失败。该问题与项目路径或编译代码无关。在账户限制解除前，不要把失败误判为编译错误。

## SingleVPN 当前状态

- 当前诊断版本：v2.1-43。
- 目标：调整 iOS 状态栏“返回 XX”提示的纵向偏移，避免与 NiceBarX 时间信息重叠。
- 已确认 Dopamine iOS 17 上 breadcrumb provider 会触发，但返回 action 集合为空。
- App 进程内 Hook `UIStatusBarSystemNavigationItemView` 没有收到布局回调，因此已撤销全 App 注入思路。
- v2.1-43 只注入 SpringBoard/设置，并在事件触发时记录 `STUIStatusBar*` 显示项和运行时结构。
- 待 GitHub Actions 恢复后重新编译 v2.1-43，并自动下载 rootless deb 到 Downloads 供设备测试。

## 用户环境与交付偏好

- 设备系统：iOS 17.0。
- 越狱：Dopamine rootless。
- 架构称呼：rootfull、rootless、roothide。
- 每次 GitHub 编译成功后自动下载 rootless deb 到 `C:\Users\liqiang\Downloads`。
- 仓库默认设为私有。
- 对第三方源码保留借鉴声明。

## 本地未跟踪资料

以下内容属于本地资料或生成物，目录迁移时特意没有上传父仓库：

- `LechengSplashSkip/artifacts`
- `ZhixingUpdateBlocker/analysis-tools`
- 各项目的 `packages`、`.theos`、deb、IPA、日志和其他构建缓存

处理这些内容前先确认用途，避免污染 Git 历史或公开敏感分析材料。
