# 验证记录

日期：2026-09-20。环境：Xcode 26.5 / Swift 6.3.2 编译器；Package 沿用 Swift 5 language mode，最低 iOS 15。

| 验证 | 结果 |
| --- | --- |
| 独立 Pager Package 单元测试，iOS 18.6 模拟器 | 最终 25 个测试通过，3 个 suite；包括一个含 3 个参数的测试 |
| 独立示例 UIKit / SwiftUI UI 测试，iOS 18.6 | 4 条手势路径通过 |
| 独立示例 UIKit / SwiftUI UI 测试，iOS 26.5 | 最终回归 4 条路径通过，0 failures |
| 核心 Sources，Swift 5 / iOS 15 simulator target 类型检查 | 通过，0 diagnostics |
| SwiftFormat | 通过 |
| SwiftLint 0.59.1 | 0 violations |

## 单元测试覆盖

页面工厂惰性调用、同 ID 保留、跨多页跳转、无效输入原子性、真实 UIKit appearance 的完成/取消/父容器离场、尺寸变化、页面移除、整个容器释放、回调重入及较新选择优先；分类栏选择意图、indicator 插值和等宽布局；吸顶临界点、短/空列表、公共头部同步、阅读位置、刷新 inset 增量、动态头部高度与解除接入清理。

## 手势路径

1. 从公共头部开始竖直拖动、列表继续滚动、切页后返回原阅读位置。
2. 头部高度变化、横向滑动、空列表吸顶及刷新。
3. 吸顶状态小幅下拉不刷新；展开后只刷新当前 Tab；短列表刷新。
4. SwiftUI UIViewControllerRepresentable 宿主中的横滑、分类切换和刷新。

[展开状态截图](Images/expanded-header.png) · [吸顶状态截图](Images/pinned-tabs.png)

## 复现

在仓库根目录运行，destination 换成本机可用模拟器：

```sh
xcodebuild test -scheme Pager \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.6'

xcodebuild test \
  -project Examples/PagerDemo/PagerDemo.xcodeproj \
  -scheme PagerDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'

swiftformat .
swiftlint --config .swiftlint.yml
```

测试通过不等于稳定版本已发布。最低 iOS 15 已做编译可用性检查，本轮未在 iOS 15 runtime 上执行；真机性能、VoiceOver 完整交互和极端内存压力仍需后续验证。示例截图来自实际 UI 测试，不是设计稿。
