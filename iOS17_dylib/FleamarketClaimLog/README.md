# 闲鱼领取诊断 0.6.0

只注入 `com.taobao.fleamarket`；只读记录请求和屏幕出现的两种领取失败文案时间，不更改请求、响应或设备环境。日志位于闲鱼沙盒 `Documents/FleamarketClaimLog.log`。0.6.0 根据 0.5.0 日志中 WindVane 只出现 `WVTBUserTrack/toUT2` 埋点、点击领奖后未出现业务桥接调用的证据，在 `mtop.taobao.idle.treasure.hunt.map.init` 出现后的 60 秒内记录 `FMMtopResponseModel` 的 `returnDO` 和 `userInfo` 白名单错误字段。响应模型事件不能直接归属某一个 API，必须结合时间和接口名解释。保留 WebView 和桥接诊断以确认页面调用路径。日志不记录调用参数、账号信息或完整响应；替换 dylib 后须彻底关闭并重开闲鱼，再进入活动页。

日志不包含 URL 查询参数、请求头、Cookie、Token、设备标识或原始响应正文；只提取服务端 `ret`、`code`、`msg` 等错误结果字段（字符串截断为 180 字符）。请仍在分享前核对日志。日志上限 1 MiB，超过后停止记录而非删除已有数据；卸载插件不自动删除日志。

请在安装后重启闲鱼，记录一次点击“领取”的准确时间，再从 Filza 导出上述日志。失败不必然意味着设备检测：需以实际服务端返回码区分登录、资格、当日限额、活动状态或设备风险。
