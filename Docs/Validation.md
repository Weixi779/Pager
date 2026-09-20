# 验证记录

日期：2026-09-20。环境：Xcode 26.5 / Swift 6.3.2 编译器；Package、示例 App 和 UI 测试均使用 Swift 6 language mode，最低 iOS 16。

| 验证 | 结果 |
| --- | --- |
| 独立 Pager Package 单元测试，Swift 6 / iOS 18.6 模拟器 | 25 个测试通过，3 个 suite；包括一个含 3 个参数的测试；Swift 警告视为错误 |
| 核心交接修复后的 Pager Package 单元测试，Swift 6 / iOS 16.4、26.5 模拟器 | 两个系统分别 36 个测试通过，5 个 suite；Swift 警告视为错误；释放测试显式排空 autorelease pool 后检查弱引用 |
| 导航协议抽取后的 Pager Package 单元测试，Swift 6 / iOS 16.4 模拟器 | 42 个测试通过，6 个 suite；包括自定义 UIView 导航实现的注入和状态同步；Swift 警告视为错误 |
| 子页面 appearance 重入与分类栏缩窄修复，Swift 6 / iOS 16.4、26.5 模拟器 | 两个系统分别 45 个测试通过，7 个 suite；Swift 警告视为错误 |
| 原生区头与状态栏修复，Swift 6 / iOS 16.4、26.5 模拟器 | 两个系统分别 48 个测试通过，8 个 suite；Swift 警告视为错误 |
| 非抛出 API 与控制协议收口，Swift 6 / iOS 16.4 模拟器 | 51 个测试通过，9 个 suite；普通拒绝无副作用、初始配置惰性、公开能力和弱 delegate 已验证 |
| 非抛出 API 与控制协议收口后的示例 UI 测试，Swift 6 / iOS 26.5 | UIKit / SwiftUI 共 4 条路径通过，0 failures |
| 分类栏下方刷新布局，Swift 6 / iOS 16.4 | 完整 53 个测试通过，9 个 suite；新增下拉空间及原生刷新位置的参数化回归测试 |
| 分类栏下方刷新布局，Swift 6 / iOS 26.5 | Sticky、原生集成及状态交接共 18 个测试通过，3 个 suite |
| 分类栏下方刷新布局后的示例 UI 测试，Swift 6 / iOS 26.5 | UIKit / SwiftUI 原有 4 条手势路径通过，0 failures |
| 外部模块 API 编译检查，Swift 6 / iOS 16.0 target | 查询、delegate、单参数选择和独立 Pager 更新可编译；组合 pager 和 delegate 参数直接调用 setPages 均被编译器拒绝 |
| 首版示例 UIKit / SwiftUI UI 测试，Swift 5 / iOS 18.6 | 历史验证：4 条手势路径通过 |
| 独立示例 UIKit / SwiftUI UI 测试，Swift 6 / iOS 26.5 | 生命周期、几何与接管修复、导航协议抽取，子页面重入与分类栏缩窄修复，以及原生区头与状态栏修复后，4 条路径通过，0 failures |
| 核心 Sources，Swift 6 / iOS 16.0 simulator target 类型检查 | warnings-as-errors，0 diagnostics |
| SwiftFormat 0.61.0 | 通过 |
| SwiftLint 0.63.2 | strict，0 violations |

Swift 6 模式自带完整并发检查；本次未新增跳过隔离检查的标注。没有 Swift 源码诊断；Xcode 仍有 AppIntents 元数据提取提示（本包不依赖 AppIntents）及已签名测试框架跳过 stripping 的工具链提示。

iOS 16.4 的 UIKit 会保留部分 autoreleased 临时引用。页面移除和容器释放测试在明确的 autorelease pool 边界后断言释放，保留原有弱引用和页面保留断言；不以跳过断言或固定延时掩盖持有关系问题。

## 单元测试覆盖

页面工厂惰性调用、同 Id 保留、跨多页跳转、无效输入原子性、真实 UIKit appearance 的完成/取消/父容器离场、尺寸变化、页面移除、整个容器释放、回调重入及较新选择优先；分类栏选择意图、indicator 插值和等宽布局；吸顶临界点、短/空列表、公共头部同步、阅读位置、刷新 inset 增量、动态头部高度与解除接入清理。

本轮新增 7 个边界测试（含参数化用例）：提前加载/选择时补接全部已创建列表且工厂只运行一次；初始零尺寸后的分类可见性；分类重排后的选择可见性；进度更新保留分类栏手动滚动位置；已加载/未加载及清空页面时的回调快照；无效输入/过渡中替换的失败原子性；回调重入拒绝替换、延后选择及较新选择优先。测试先在修复前确认失败，再验证修复后通过。

本轮另外加入 4 个状态交接测试（含参数化用例）：从切页开始/结束/选择回调触发离场并重新出现；横向过渡中在吸顶、部分收起、下拉位置调整头部；零高度头部变为可见后保留阅读位置；立即复用已释放容器的页面，验证新旧 inset 贡献和配置恢复。三个缺陷在修复前已复现，修复后在 iOS 16.4、26.5 均通过。

导航协议抽取新增 6 个测试（含参数化用例）：注入外部 UIView 后的挂载、提前选择、点击意图、进度与取消；已加载/未加载以及清空页面时的回调一致性；校验或过渡状态拒绝更新时不调用外部配置；导航配置回调的重入保护；协议 existential 的通用事件分发；初始化身份顺序不匹配时保留外部视图原选择。

子页面重入修复新增 3 个测试（其中两项分别覆盖 4 个生命周期回调）：切页与 `setPages` 期间从子页面 `viewWillAppear` / `viewWillDisappear` / `viewDidAppear` / `viewDidDisappear` 触发父容器离场，断言完整 appearance 顺序、结束事件唯一性、最终选择和再次入场；分类栏从 640pt 缩窄到 160pt 后仍展示选中项，随后进度更新和普通布局保留手动滚动位置。

原生集成修复新增 3 个测试：使用真实 UITableView plain section header 与 UICollectionViewFlowLayout pinned section header，验证完整展开/收起往返、深滚动、头部与分类栏高度变化及解除接入后的区头位置；状态栏测试在主线程同步范围内临时拦截 UIKit 更新调用并立即恢复，检查选择变更与清空页面都会请求更新。未为测试新增生产 API。

非抛出 API 改造将普通拒绝断言迁移为 Bool，保留旧状态与配置闭包不执行等检查；另加 3 个仅 import Pager 的公开 API 测试，验证拒绝页面替换不创建页面、不发事件，拒绝导航项更新保留内容与选择，以及控制协议的选择便利调用、状态查询和弱 delegate。初始化采用非 Optional 并信任调用方，因此历史上的初始化拒绝用例改为合法初始化的选择同步与工厂惰性检查。实现契约不再使用 precondition/assert，非法初始配置不属于可恢复更新的测试保证。

本轮未处理 `PagerTabBar` 的 Dynamic Type 字体测量不一致问题；该已知问题不计入上述通过结果。

分类栏下方刷新修复：先在旧实现上复现 header/bar 随下拉偏移，再验证它们在完全展开后保持原位，新增空间位于分类栏与列表内容之间。参数化测试覆盖额外顶部 inset、不同下拉距离、下拉中改变头部高度，以及 UIScrollView / UITableView / UICollectionView 的真实 UIRefreshControl 位置、刷新中切页和结束后的 inset 恢复。横向过渡中的头部高度测试同步采用新的顶部边界。刷新位置直接在原生视图集成测试中断言；XCUITest 会等待刷新动画结束，因此不依赖 UI 自动化在动画中途抓取控件。

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
  -destination 'platform=iOS Simulator,name=iPhone 14 Pro,OS=16.4' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

xcodebuild test \
  -project Examples/PagerDemo/PagerDemo.xcodeproj \
  -scheme PagerDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_SUPPRESS_WARNINGS=NO

swiftformat . --lint --cache ignore
swiftlint lint --strict --no-cache --config .swiftlint.yml
```

测试通过不等于稳定版本已发布。最低 iOS 16.0 已做编译可用性检查，单元测试运行于 iOS 16.4 runtime，UI 测试运行于 iOS 26.5 runtime；本轮未在 iOS 16.0 runtime 上执行。真机性能、VoiceOver 完整交互和极端内存压力仍需后续验证。示例截图来自实际 UI 测试，不是设计稿。
