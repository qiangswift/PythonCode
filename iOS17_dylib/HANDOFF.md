# iOS17_dylib 项目交接

最后更新：2026-08-27

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

当前用于 iOS 插件构建的新私有仓库：`qiangswift/PythonCode`，分支 `main`。该仓库采用当前 `iOS17_dylib` 项目快照，不包含旧仓库的大体积历史。

旧父仓库：`swiftss/PythonCode`，本地仍保留其历史和远程。

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

### AwemeCameraEnhancer 1.2.0

- GitHub Actions run `33042318144` succeeded in `qiangswift/PythonCode`.
- Removed the delayed runtime Live Photo experiment scan that could dismiss the first camera entry.
- Native Live Photo mode/capture hooks now request mode `1`; the callback saves photo and paired-video resources together, then returns to the camera and displays a save toast.
- Settings entry now covers the old and new Douyin settings controller classes.
- Rootless package: `C:\Users\liqiang\Downloads\com.swiftss.awemecameraenhancer_1.2.0_iphoneos-arm64.deb`.

以下父仓库工作流已更新为 `iOS17_dylib/<ProjectName>/` 路径：

- `china-mobile-splash-ad-blocker.yml`
- `lecheng-splash-skip.yml`
- `singlevpn-build.yml`
- `zhixing-update-blocker.yml`

`qiangswift` 账号的 GitHub-hosted Actions 可正常运行。2026-08-27 已成功编译 AwemeCameraEnhancer、PhoenixVideoAdSkip、LechengSplashSkip、ChinaMobileSplashAdBlocker 和 ZhixingUpdateBlocker。

PhoenixVideoAdSkip 1.1.1 正在修正“商城”Tab 实际路由到福利页导致按控制器过滤未命中的问题；新策略会同步过滤底栏类型、可见性和最终呈现下标。

## SingleVPN 当前状态

- 当前开发版本：v2.1-45。
- 设置首页流量统计使用 2×2 视觉网格：第一行依次显示 `5G↑`、`WiFi↑`，第二行依次显示 `5G↓`、`WiFi↓`。上下行均使用普通文本箭头，不使用 emoji，并取消依赖空格补齐的单标签布局。
- 目标：调整 iOS 状态栏“返回 XX”提示的纵向偏移，避免与 NiceBarX 时间信息重叠。
- 已确认 Dopamine iOS 17 上 breadcrumb provider 会触发，但返回 action 集合为空。
- App 进程内 Hook `UIStatusBarSystemNavigationItemView` 没有收到布局回调，因此已撤销全 App 注入思路。
- 返回按钮继续保持 SpringBoard 侧安全诊断；下一步结合设备上的 SpringBoard、StatusStatusUI、StatusBar 和 NiceBarX 二进制确认实际显示项后再应用偏移。
- v2.1-45 已由新私有仓库 `qiangswift/PythonCode` 的 Actions run `33052429804` 成功编译 rootfull、rootless、roothide。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-45_iphoneos-arm64.deb`。
- 设备提取的 `SpringBoard` 是约 119 KB 的启动壳；`归档.zip` 只有 SpringBoard 系列 framework 资源，没有 StatusStatusUI、StatusBar 或 NiceBarX 可执行二进制。返回按钮下一步优先分析 NiceBarXBase/BarXSBoard dylib；系统私有框架代码可能需要从 arm64e dyld shared cache 提取。

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
