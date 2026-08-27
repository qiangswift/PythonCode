# Lecheng Splash Skip

适用于乐橙 `8.12.1`（Bundle ID：`com.dahuatech.lecheng`）的 rootless 越狱插件。

插件分别调用应用自身的两条启动广告关闭路径：

- `LCAPIADViewController -skipAdBtnClick`：联网/API 启动广告。
- `LCAdLoadViewController -cancelAdBtnClick`：本地缓存及无网倒计时启动图。

`1.0.1` 会在这两个广告页面绘制前先隐藏其根视图，消除执行原生关闭回调前短暂闪现的一帧图片。

`1.0.2` 通过设备预览页自身的显示判定，默认关闭设备详情页中的增值服务及云存储横幅，并让下方内容使用原生的“无横幅”布局。

没有屏蔽全局网络请求，也没有修改通用 `UIViewController` 生命周期，以降低卡启动和崩溃风险。

安装生成的 rootless `.deb` 后，彻底关闭乐橙进程并重新启动。若目标应用更新后类名或流程改变，需要针对新版本重新适配。
