# Changelog

## 0.3.0 — 2026-10-17

- Add `expandedTopOffset(of:)` for an attached page's stable, fully expanded origin, excluding refresh-owned space. It returns nil for unattached pages or during horizontal transitions.
- Add `PagerViewControllerDelegate.pager(_:didCommit:)`, called after the source disappears and before the destination appears. Cancellation does not commit; existing delegates use an empty default implementation.
- Keep appearance transitions open when a drag resumes during deceleration. Interpolate the visible neighboring tabs across multi-page swipes.
- Cover completion, reversal, interruption, reentrant selection, and expanded-origin behavior.

The default `PagerTabBar`, custom navigation protocol, iOS 16 baseline, and Swift 6 language mode are retained. No external dependencies are added.

Validation: 67 package tests, 8 cross-package refresh integration tests, and all 4 existing UIKit/SwiftUI demo UI tests passed with Xcode 27.1 on iOS 27.0. See [validation](Docs/Validation.md) for historical results and known limitations, including the existing default-tab Dynamic Type font-measurement limitation.

Earlier release notes: [0.2.0](https://github.com/Weixi779/Pager/releases/tag/v0.2.0) and [0.1.0](https://github.com/Weixi779/Pager/releases/tag/v0.1.0).
