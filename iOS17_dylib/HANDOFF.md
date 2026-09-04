# iOS17_dylib 项目交接

## QDReaderAutoCheckin 1.5.7

- The bookshelf game entry is removed from the native button stack and guarded
  against later asynchronous reinsertion.
- The check-in circle and glyph are smaller to match the neighboring search
  control.
- Chapter-card balance refresh mirrors QDReader's own signed
  `/argus/api/v3/user/getaccountpage` request and publishes `ChapterCard`
  immediately; the rendered Mine account cell remains only a fallback.
- Only the RootHide package is requested for this release. Compilation and
  on-device behavior must be reported separately.

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

## SingleVPN v2.1-48 breadcrumb 精确诊断

- v2.1-47 设备日志确认 `SBDeviceApplicationSceneStatusBarBreadcrumbProvider` 每次返回空集合，且 `UIStatusBarBreadcrumbItemView` 从未实例化，旧偏移 Hook 没有命中。
- 实际可见状态栏为 `STUIStatusBar` / `STUIStatusBarForegroundView`，NiceBarX 流量视图类为 `BorderLabel`。
- v2.1-48 逐项记录 `STUIStatusBar._items`、`_displayItemStates` 和 `_regions`，监听 `STUIStatusBarStringView` 文本变化，并记录 `STUIStatusBarImageView` 的图像、frame 和父视图链。
- 新私有仓库提交：`664805fd`；GitHub Actions run：`33062112668`，rootfull、rootless、roothide 均成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-48_iphoneos-arm64.deb`。

## SingleVPN v2.1-49 navigation 偏移候选

- v2.1-48 日志已确认真实目标是 `STUIStatusBarNavigationItem` 位于 `bottomLeading` 区域的 `STUIStatusBarStringView`，示例文字为 `◀︎ 微信🔒` 和 `◀︎ Telegram`。
- v2.1-49 在该字符串视图的 `setText:` 与 `layoutSubviews` 中识别 `◀`，仅对该视图应用设置的 Y 偏移；时间、NiceBarX 流量、网络和电池视图不受影响。
- 已停用 v2.1-48 高频 STUI 全量诊断，只保留版本载入及目标偏移命中日志。
- 新私有仓库最终提交：`01075f25`；成功 Actions run：`33062871943`（前一次 run `33062682162` 因残留未初始化诊断组而失败，未生成包）。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-49_iphoneos-arm64.deb`。

## SingleVPN v2.1-50 frame 偏移与流量布局

- 用户测试 v2.1-49 的 transform 偏移视觉上没有生效；StatusStatusUI 后续布局会管理该属性。
- v2.1-50 改为 Hook 目标 `STUIStatusBarStringView.setFrame:`，对含 `◀` 的 navigation 文本将 Y 偏移合并进系统最终 frame。
- 设置首页流量两列改为右对齐，列间布局 gap 从 8 缩至 2，左列占比从 44% 调为 42%。
- 新私有仓库提交：`cb71cd8b`；GitHub Actions run：`33063583926`，三种构建成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-50_iphoneos-arm64.deb`。
- 各项目的 `packages`、`.theos`、deb、IPA、日志和其他构建缓存

处理这些内容前先确认用途，避免污染 Git 历史或公开敏感分析材料。

## SingleVPN v2.1-46 状态栏返回按钮定位

- iPhone 15 Pro（iPhone16,1）、iOS 17.0（21A327）的完整 arm64e dyld shared cache 已在本地只读分析。
- `SBDeviceApplicationSceneStatusBarBreadcrumbProvider` 位于 SpringBoard，负责生成返回动作；最终可见控件是 UIKitCore 的 `UIStatusBarBreadcrumbItemView`，继承 `UIStatusBarSystemNavigationItemView`，内部持有 `UIButton`。
- v2.1-46 改为仅在 SpringBoard 精确 Hook `UIStatusBarBreadcrumbItemView`，将设置的纵向偏移应用于内部按钮 transform，不移动整个状态栏。
- 新私有仓库提交 `ab5ffe4b`；GitHub Actions run `33060278809` 的 rootfull、rootless、roothide 均构建成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-46_iphoneos-arm64.deb`。

## SingleVPN v2.1-51 navigation geometry fallback

- v2.1-50 设备日志中返回文字发生编码混乱，Unicode `◀` 条件没有命中，也没有产生 `navigation offset applied` 记录。
- v2.1-51 改用已经确认的 `bottomLeading` 几何特征识别 `STUIStatusBarStringView` 返回项，同时保留可用时的 Unicode 判断。
- 删除高频 `status string changed` 诊断日志；命中目标后仍保留精简的偏移日志。
- 私有仓库提交：`b77ef919`、编译修复 `eb27c863`；GitHub Actions run `33064165215` 的 rootfull、rootless、roothide 均构建成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-51_iphoneos-arm64.deb`。

## SingleVPN v2.1-52 流量摘要紧凑对齐

- 取消按屏幕宽度 42%/58% 分割流量两列，改为分别按 `5G` 与 `WiFi` 两列的实际内容宽度布局，固定列间距为 10pt。
- 两列使用等宽字体并左对齐，使每列上下两行的箭头、冒号和数值起点一致；整个流量组相对“设置”标题向右间隔 24pt。
- 私有仓库提交：`977b2314`；GitHub Actions run `33064711359` 的 rootfull、rootless、roothide 均构建成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-52_iphoneos-arm64.deb`。

## SingleVPN v2.1-53 返回文字向下溢出

- v2.1-51 已确认负偏移可向上移动，但正偏移在状态栏下边界被父级裁剪。
- v2.1-53 在识别到 `STUIStatusBarStringView` 返回项时，解除该视图到 `STUIStatusBar` 之间父链的 `clipsToBounds` 与 `masksToBounds`，使正值可以继续向下显示。
- 私有仓库提交：`89df30c5`；GitHub Actions run `33065175626` 首次 Release 遇到 GitHub Unicorn 临时错误，attempt 2 的 rootfull、rootless、roothide 和 Release 均成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-53_iphoneos-arm64.deb`。

## SingleVPN v2.1-54 数值右对齐与内部文字位移

- v2.1-53 测试确认 `-10` 的 frame 上移有效，但 `+8` 仍被 StatusBar 外部布局边界抵消；仅解除父级裁剪不足以解决。
- v2.1-54 不再移动 navigation view 的 frame，改为在 `setFrame:` 与 `layoutSubviews` 完成后设置内部 `bounds.origin.y = -offset`，正值移动文字内容向下、负值向上。
- 流量摘要每组拆为固定前缀标签和独立右对齐数值标签，使不同位数的 `xx.xxG` 以末尾 `G` 对齐。
- 私有仓库提交：`77f8f5e8`；GitHub Actions run `33065989085` 的 rootfull、rootless、roothide 均构建成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-54_iphoneos-arm64.deb`。

## SingleVPN v2.1-56 图层位移与 WiFi 垂线锚定

- v2.1-54 的 `bounds.origin` 测试在 `+8` 时仍无视觉变化；v2.1-55 改用 CALayer translation，但因未链接 QuartzCore 而构建失败，未交付测试。
- v2.1-56 链接 QuartzCore，并在每次目标布局后应用 `CATransform3DMakeTranslation(0, offset, 0)`；日志关键字改为 `navigation layer offset applied`。
- 设置页流量摘要的最右侧锚定到屏幕宽度 80.5%（iPhone 15 Pro 状态栏 WiFi 图标中心垂线），内容长度变化时向左扩展。
- 私有仓库提交：`a4dc0638`；GitHub Actions run `33066569437` 的 rootfull、rootless、roothide 均构建成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.1-56_iphoneos-arm64.deb`。

## SingleVPN 2.2.0 稳定版

- 用户实机确认 v2.1-56 的返回文字 CALayer 偏移、流量数值右对齐及 WiFi 垂线锚定效果正确。
- 稳定版保留已验证功能，删除约 379 行诊断代码，包括日志文件写入、运行时类/方法扫描、provider 探针、视图树遍历、延迟重试及旧 breadcrumb Hook。
- 返回文字纵向偏移的全新默认值为 `+7.6`；已有用户保存值不会被覆盖。
- 安装脚本只清理历史调试文件 `com.82flex.singlevpn.breadcrumb.log` 与 `SingleVPNBreadcrumb.log`，正式版不再生成这些日志。
- 私有仓库提交：`ff0b00f7`；GitHub Actions run `33067785744` 的 rootfull、rootless、roothide 及 Release 均成功。
- rootless 正式包：`C:\Users\liqiang\Downloads\com.82flex.singlevpn_2.2.0_iphoneos-arm64.deb`。

## QDReaderAutoCheckin 1.2.7 自有商业开屏

- 对 QDReader App Store 5.9.474 砸壳包确认截图中的书籍推广走起点自有 `QDCommercialSplashHelper -> QDSplashView`，不是 Pangle/GDT。
- 新版通过 `shouldShowCommercialSplashAd` 与 `showCommercialSplashScreen` 两个原生布尔决策入口报告“本次不展示”，同时设置本次启动状态；不截断无返回值的加载/展示流程，避免启动协调器卡死。
- 独立旧仓库提交：`ecd3aa4`，但 `swiftss` Actions run `33071235798` 因账户 billing 限制未启动任何构建步骤。
- 源码快照与新工作流已提交至私有仓库 `qiangswift/PythonCode`，提交：`f1c8e20b`；Actions run `33071383122` 的 rootfull、rootless、roothide 均成功。
- rootless 测试包：`C:\Users\liqiang\Downloads\com.swiftss.qdreaderautocheckin_1.2.7_iphoneos-arm64.deb`。
