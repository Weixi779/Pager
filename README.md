# Pager

English | [简体中文](README_CN.md)

A UIKit page container with lazy retained pages, customizable tabs, and a shared collapsing header. Each page keeps its native vertical scrolling; your app owns its content and refresh requests.

**iOS 16+ · Swift 6 · Swift Package Manager · No third-party dependencies**

## Preview

Screenshots from the included UIKit demo:

<table>
  <tr><th>Expanded header</th><th>Pinned tabs</th></tr>
  <tr>
    <td><img src="Docs/Images/expanded-header.png" width="280" alt="Shared header expanded above the tabs and list"></td>
    <td><img src="Docs/Images/pinned-tabs.png" width="280" alt="Tabs pinned above the scrolling list"></td>
  </tr>
</table>

Scroll from the header into the list, switch between retained pages, and pull to refresh below the tab bar. Short and empty lists can also reach the pinned position.

## Components

The package exports one library, `Pager`:

| API | Responsibility |
| --- | --- |
| `PagerViewController` | Horizontal paging, lazy page creation, retained controllers, and child lifecycle forwarding. |
| `PagerTabBar` | Configurable titles, selection, and an interpolating indicator. |
| `PagerNavigationPresenting` | A contract for supplying your own navigation UIView. |
| `StickyPagerViewController` | Shared header, pinned navigation, and coordination with each page's vertical scroll view. |
| `PagerControlling` | Page selection, queries, and events; the composite exposes this interface without page replacement. |

## Quick Start

Requires Swift 6 / Xcode 16 or later and iOS 16 or later. Add the package in Xcode, or declare it in `Package.swift`:

```swift
.package(url: "https://github.com/Weixi779/Pager.git", from: "0.3.0")
```

Add the product to your target:

```swift
.product(name: "Pager", package: "Pager")
```

### Horizontal paging

Create page descriptors with stable identities. Replace the empty controllers below with your own screens:

```swift
import Pager
import UIKit

let pager = PagerViewController(pages: [
    PagerPage(id: "featured") { UIViewController() },
    PagerPage(id: "discover") { UIViewController() },
])
pager.selectPage("discover", animated: false)
```

Embed it using standard UIKit containment: `addChild`, add and lay out its view, then `didMove(toParent:)`. Page factories run when needed. A retained Id keeps the same controller across page updates; use a new Id when replacing the controller itself.

### Shared header and pinned tabs

```swift
let sticky = StickyPagerViewController(
    pages: [
        PagerPage(id: "featured") { UITableViewController(style: .plain) },
        PagerPage(id: "discover") { UITableViewController(style: .plain) },
    ],
    items: [
        .init(id: "featured", title: "Featured"),
        .init(id: "discover", title: "Discover"),
    ],
    headerView: UIView(),
    headerHeight: 200,
    scrollViewProvider: { _, controller in
        (controller as! UITableViewController).tableView
    }
)

sticky.pager.selectPage("discover")
```

Use your own table controllers and header view for real content. The provider above relies on the page types supplied by the factories. Return the page's main `UITableView`, `UICollectionView`, or `UIScrollView`, filling its viewport without another vertical scrolling ancestor.

The composite handles safe areas and its own inset contribution. Your page retains its scroll delegate. Use `sticky.setContentInset(_:for:)` for business padding changes after attachment, and `sticky.setHeaderHeight(_:)` when the measured header height changes.

### Customize navigation

```swift
var configuration = PagerTabBar.Configuration()
configuration.indicatorColor = .systemBlue
configuration.indicatorWidth = 20
configuration.itemSpacing = 24
sticky.tabBar.configuration = configuration
```

For a different navigation design, implement `PagerNavigationPresenting` on your UIView and supply it through the `tabBar:` initializer. The default `PagerTabBar` is optional. See the [integration guide](Docs/Pager.md) for the protocol and update contracts.

### Header state and returning to the expanded top

Read `sticky.headerState` for `collapseDistance`, `collapseRange`, and `progress`.
Use `onHeaderStateChange` to drive opacity or icon transitions; the container still owns header positioning.
The callback runs synchronously after geometry updates and only when the state changes.
Horizontal paging keeps the displayed header state fixed until completion or cancellation.
A zero-height header and pull-down beyond the expanded top both report zero progress.
Read the current state when installing a handler after the view has loaded.

```swift
sticky.onHeaderStateChange = { state in
    // Update feature-owned visuals using state.collapseDistance or state.progress.
}
let accepted = sticky.scrollToTop(of: "feed", animated: true)
```

Returning to the top uses the fully expanded origin, not the changing `adjustedContentInset.top`.
It does not select or load a page, start a refresh, or remove temporary space owned by a refresh control.
It returns false for unattached pages or during horizontal transitions; true means the request was accepted,
not that the animation finished. Page alignment preserves an existing pull-down region without consulting
network request state or depending on a particular refresh control.

### Refresh below the tab bar

Install a `UIRefreshControl` on each page's main list, handle `.valueChanged`, and call `endRefreshing()` when the request finishes.

Once the list returns to the top and the shared header is fully expanded, further pulling keeps the header and tabs stationary. The list moves down, exposing the refresh indicator **between the tabs and list content**. Each page owns its refresh state; switching tabs does not refresh another page.

## Behavior and Boundaries

- Initial page Ids must be unique; any selected Id must belong to the pages. Navigation Ids and order must match. Initializers trust these caller contracts.
- Runtime `setPages` / `setItems` updates return `Bool`; rejected updates leave the previous state intact. Update composite pages through `sticky.setPages`, keeping navigation synchronized.
- `selectPage` returning `true` means the request was accepted. Completion and cancellation arrive through `PagerViewControllerDelegate` events.
- Created pages remain retained until removed or the container is released. There is no LRU eviction policy in this release.
- Ordinary paging supports arbitrary child controllers. Sticky coordination requires an explicitly supplied UIKit scroll view; it does not discover SwiftUI `List` internals.
- Your app owns requests, loading state, content, and styling. Third-party refresh libraries have not been individually validated.

## Example and Validation

```sh
open Examples/PagerDemo/PagerDemo.xcodeproj
```

Use **PagerDemo** for UIKit or **PagerDemoSwiftUI** to host the same component through `UIViewControllerRepresentable`. The demo includes long, short, and empty lists, header resizing, page switching, and native refresh.

Version 0.3.0: 67 package tests, 8 cross-package refresh integration tests, and 4 demo UI tests passed with Xcode 27.1 on iOS 27.0. SwiftLint reports no violations. See the [validation record](Docs/Validation.md) for historical environments, commands, and known limitations.

## Roadmap

Version 0.1.0 is the first release. APIs may evolve before 1.0; the items below describe future directions, not shipped configuration options or a release schedule.

- [x] Lazy retained UIKit pages, customizable navigation, and shared sticky headers.
- [x] Per-page native refresh below the tabs, with short/empty-list support.
- [x] A SwiftUI host example and gesture coverage.
- [ ] A reusable SwiftUI adapter with `Binding<PagerPageId?>` selection: reuse the UIKit container, publish committed selection changes, and avoid feedback loops during SwiftUI updates.
- [ ] SwiftUI page content through `UIHostingController`, preserving stable page identity across view updates. Explore declarative header and navigation composition without recreating the pager on each render.
- [ ] An explicit scroll-coordination boundary for SwiftUI sticky layouts. Evaluate public scroll APIs and deployment requirements before promising `List` / `ScrollView` support; avoid relying on private view-tree structure.
- [ ] Dynamic Type sizing improvements and broader VoiceOver, right-to-left, and device validation.
- [ ] Evaluate bounded page retention and collection-based hosting when real memory and scale requirements justify them.

The intended SwiftUI extension is an optional layer over the UIKit core: reuse its identity, selection, and lifecycle behavior while keeping application data loading and refresh state in the application.

## Documentation

- [Integration contracts and architecture](Docs/Pager.md) (Chinese)
- [Demo guide](Examples/PagerDemo/README.md) (Chinese)
- [Validation record](Docs/Validation.md) (Chinese)
- [Release notes](https://github.com/Weixi779/Pager/releases)

## License

Pager is available under the [Apache License 2.0](LICENSE).
