# PagerDemo

独立 UIKit 验证 App，只依赖相对路径 `../..` 的 Pager。最低 iOS 16，使用文件系统同步 group，不依赖任何宿主工程。

打开 `PagerDemo.xcodeproj`，选择 **PagerDemo** scheme 和可用 iOS Simulator。测试也使用这个 scheme。

```sh
xcodebuild test -project PagerDemo.xcodeproj -scheme PagerDemo \
  -destination 'platform=iOS Simulator,name=<本机设备名称>'
```

页面包括：精选（长列表）、发现（两行）、分类（空列表）。

检查：从公共头部向上拖动并保持惯性；分类栏吸顶后列表继续滚动；横滑/点击切页；吸顶时返回旧页；展开头部后下拉刷新当前页；短/空列表的吸顶和刷新；头部高度变化与横竖屏变化。UI 测试覆盖主要手势路径，并在结果包中保留截图。

展开头部后继续下拉，公共头部和分类栏保持原位，刷新指示器显示在分类栏与列表之间。

实际动画观感与设备性能仍需在目标设备上复核；自动化断言不等同于所有手势组合都已验证。

`PagerDemoSwiftUI` scheme 用 SwiftUI 的 UIViewControllerRepresentable 嵌入同一 UIKit 示例。桥接仅存在于示例，核心 Package 不引入 SwiftUI API。UI 测试同时覆盖 UIKit 和 SwiftUI 宿主。
