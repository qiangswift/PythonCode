# iOS17_dylib 工作规范

## 适用范围

本文件适用于本目录及其全部子目录。今后所有与 iOS、越狱插件、Theos、dylib、deb、IPA 分析有关的项目，统一存放并在本目录内开发：

`C:\Users\liqiang\Documents\PythonCode\iOS17_dylib`

不要再在 `C:\Users\liqiang\Documents\PythonCode` 根目录新建同类项目。新项目应使用独立、语义明确的子目录。

## 目标环境

- 主要测试设备：iOS 17.0。
- 主要越狱环境：Dopamine rootless。
- 用户明确要求时，同时提供 rootfull、rootless 和 roothide 三种构建结果。
- `roothide` 不得写成 `roothide3`。
- 涉及注入过滤时，优先使用最小 Bundle ID/Executable 范围，避免无依据地全局注入。

## 开发与安全

- 修改前先阅读目标项目的 README、Makefile、control、过滤 plist、现有日志和项目内说明。
- 保留用户已有修改、砸壳 IPA、分析资料、构建产物和日志；不得擅自删除或覆盖。
- 对 SpringBoard 私有接口和全局 Hook 保持谨慎。先做最小诊断，再逐步启用功能，避免进入 Safe Mode。
- 诊断版本应标明版本号和阶段；问题确认后清理高频或无必要日志。
- 日志优先写入目标 App 的 Documents；SpringBoard 日志写入 `/var/mobile/Library/Preferences/` 下明确命名的文件。
- 不提交 IPA、deb、dylib、`.theos`、`packages`、artifacts、分析工具及其他大体积生成文件，除非用户明确要求。
- 引用第三方源码或实现思路时，在 README 或 `THIRD_PARTY_NOTICES.md` 中保留清晰的借鉴声明和来源链接。

## Git 与 GitHub

- 主仓库中的工作流路径必须以 `iOS17_dylib/<ProjectName>/` 为准。
- 独立 Git 仓库应保留各自的 `.git`、远程地址和提交历史；不要无意中把嵌套仓库作为普通文件加入父仓库。
- 仓库默认保持私有，不得擅自公开。
- 提交前只暂存当前任务涉及的文件，并运行 `git diff --check`。
- 不提交本地日志、砸壳包、下载缓存、逆向分析工具或无关工作区改动。
- GitHub Actions 成功后，按用户约定将 rootless deb 自动下载到 `C:\Users\liqiang\Downloads`。

## 构建与交付

- Theos 项目修改后至少检查 Makefile、control、过滤 plist 和安装路径是否一致。
- GitHub Actions 的触发路径、`working-directory`、产物收集路径必须随项目目录同步更新。
- 构建结果需明确区分 rootfull、rootless、roothide，并报告版本号、提交号和文件路径。
- 无法编译时应给出具体阻塞原因，不得把未运行的构建描述为成功。

## 交接

- 每次发生目录结构、仓库关系、构建方式、测试结论或重要遗留问题变化时，同步更新本目录的 `HANDOFF.md`。
- 开始新的 iOS 任务前先阅读 `HANDOFF.md`，避免重复排查已经确认的问题。
