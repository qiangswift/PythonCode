# 闲鱼领取诊断 1.1.0

1.1.0 verifies the native Block callback signature before wrapping it. Supported `void` signatures with an object response (and optionally an object or BOOL second argument) log the returned error/response while forwarding the exact original arguments to the original Block. Unsupported signatures are left untouched and logged as skipped. This needs on-device validation; a successful build alone does not verify the callback path.

1.0.0 targets `mtop.taobao.idle.task.getolivertaskbenefit` through `MtopWVPlugin.send:withCallback:withWebView:withViewController:`. It records the callback object's class and candidate result selectors to identify the native response path. For this one claim API only, it also records the bridge request payload and matching WebKit cookies locally. This version does not yet claim to capture the server response.

**Sensitive log:** The local `Documents/FleamarketClaimLog.log` can now contain complete session cookies and account-related request values. Do not post it publicly or include it in a Git commit. Share it only through a private channel and rotate the session if it leaks. The tweak does not upload the log.

只注入 `com.taobao.fleamarket`；只读记录请求和屏幕出现的两种领取失败文案时间，不更改请求、响应或设备环境。日志位于闲鱼沙盒 `Documents/FleamarketClaimLog.log`。0.9.0 根据 0.8.0 日志确认的 WebKit 消息结构 `name/reqId/params`，改为记录经字符过滤的 `name` 与 `params` 内接口标识及字段名，并对重复埋点限流；不记录 `reqId`、请求正文或任意参数值。同时补读已确认存在的 `FMMtopReturnDO.api/subErrorCode/subErrorInfo/errorInfo/bizInfo/info` 和嵌套的白名单错误字段。响应模型事件仍需按 API 和时间关联，不能仅凭临近时间推断因果。替换 dylib 后须彻底关闭并重开闲鱼，再进入活动页。

日志不包含 URL 查询参数、请求头、Cookie、Token、设备标识或原始响应正文；只提取服务端 `ret`、`code`、`msg` 等错误结果字段（字符串截断为 180 字符）。请仍在分享前核对日志。日志上限 1 MiB，超过后停止记录而非删除已有数据；卸载插件不自动删除日志。

请在安装后重启闲鱼，记录一次点击“领取”的准确时间，再从 Filza 导出上述日志。失败不必然意味着设备检测：需以实际服务端返回码区分登录、资格、当日限额、活动状态或设备风险。
