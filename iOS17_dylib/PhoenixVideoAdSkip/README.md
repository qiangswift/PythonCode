# Phoenix Video Episode Ad Skip

适用于凤凰视频 `7.2.1`（Bundle ID：`com.phoenix.video`）的 rootless 越狱插件。

插件修改应用业务层 `SSBizVideoInVideoPatchAdServiceImp -canShowAd`，在换集前贴片广告创建之前返回“不展示”。这样不会启动广告视图及约 7 秒的上滑跳过倒计时，也不影响播放器和第三方广告 SDK 的其他用途。

安装生成的 rootless `.deb` 后，彻底关闭凤凰视频进程并重新启动。App 更新后若类名或流程变化，需要针对新版本重新适配。

`1.1.0` 同时从 `SSTabBarController` 的控制器模型中移除“商城”页，并让剩余四个 Tab 使用系统原生均分布局。首次构建和服务端刷新底栏时都会执行过滤，避免商城重新出现。

`1.1.1` 针对“商城入口实际路由到福利页”的情况，进一步从底栏类型数组、可见性判定和最终呈现下标三层移除商城项，再调用原生比例重排。
