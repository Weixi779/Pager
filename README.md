# Pager

A UIKit page container with lazy retained pages, a configurable tab bar, and a shared collapsing header.

**Development preview.** API and interaction validation are in progress; no stable release has been published.

- iOS 16+, UIKit, Swift 6, Swift Package Manager; no third-party dependencies.
- `PagerViewController`: horizontal swiping, stable page Ids, lazy creation and retained controllers.
- `PagerControlling`: selection, queries and events without page replacement on the composite’s public pager.
- `PagerNavigationPresenting`: a UIView-constrained contract for externally supplied page navigation.
- `PagerTabBar`: the default implementation with titles and an interpolating indicator.
- `StickyPagerViewController`: shared header, pinned tabs and native vertical list scrolling.
- The feature owns content, styling, data loading and refresh requests.

```swift
import Pager

let pager = PagerViewController(pages: [
    PagerPage(id: "featured") { FeaturedViewController() },
    PagerPage(id: "discover") { DiscoverViewController() },
])
```

[设计契约与 Mermaid 架构](Docs/Pager.md) · [独立交互示例](Examples/PagerDemo/README.md) · [验证记录与截图](Docs/Validation.md)

Build and test the **Pager** package scheme on an iOS Simulator using Xcode 16 or later. The package, sample app and tests use Swift 6 language mode with full concurrency checking. UI state is explicitly main-actor isolated. Open `Examples/PagerDemo/PagerDemo.xcodeproj` for the sample and gesture UI tests.

This first version retains created pages. LRU eviction and UICollectionView hosting are future capabilities, not current configuration options.

## Try the development preview

```swift
.package(url: "https://github.com/Weixi779/Pager.git", branch: "main")
```

Depend on the `Pager` product. The sample also has a **PagerDemoSwiftUI** scheme for hosting the same UIKit component in SwiftUI; no SwiftUI API is added to the library.

## License

[Apache License 2.0](LICENSE).
