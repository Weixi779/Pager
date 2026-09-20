//
//  PagerStateHandoffTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Pager state handoffs")
struct PagerStateHandoffTests {
    @Test("Header resizing during a horizontal transition preserves pinning, collapse and pull-down", arguments: [CGFloat(-60), 100, 500])
    func headerResizeDuringTransition(distance: CGFloat) throws {
        let a = HandoffScrollPage(), b = HandoffScrollPage()
        let sticky = makeSticky(a: a, b: b)
        layout(sticky)
        a.scroll.contentOffset.y = distance - 244
        (sticky.pager as! PagerViewController).host.scrollView.contentOffset.x = 120
        try #require(sticky.pager.isTransitioning)
        let viewport = try #require((sticky.pager as? PagerViewController)?.view.superview)
        let expectedBefore = min(200, max(0, 200 - distance))
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport).minY == expectedBefore)
        sticky.setHeaderHeight(350)
        sticky.view.layoutIfNeeded()
        #expect(sticky.pager.isTransitioning)
        let expectedAfter = min(350, max(0, 350 - distance / 200 * 350))
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport).minY == expectedAfter)
        #expect(sticky.tabBar.superview?.bounds.height == 394)
    }

    @Test("Adding a header to a deeply scrolled page keeps shared collapse consistent")
    func zeroHeightToVisibleHeader() throws {
        let a = HandoffScrollPage(), b = HandoffScrollPage()
        let sticky = makeSticky(a: a, b: b, headerHeight: 0)
        layout(sticky)
        a.scroll.contentOffset.y = 300
        sticky.setHeaderHeight(200)
        sticky.view.layoutIfNeeded()
        let viewport = try #require((sticky.pager as? PagerViewController)?.view.superview)
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport).minY == 0)
        #expect(a.scroll.contentOffset.y == 300)
        sticky.pager.selectPage("b", animated: false)
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport).minY == 0)
        sticky.pager.selectPage("a", animated: false)
        #expect(a.scroll.contentOffset.y == 300)
    }

    @Test("Lifecycle delivery survives reentry from each transition callback", arguments: [0, 1, 2])
    func disappearanceFromSelectionCallback(callback: Int) {
        let a = HandoffLifecyclePage(), b = HandoffLifecyclePage()
        let pager = PagerViewController(pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }])
        layout(pager)
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        let recorder = HandoffDelegate()
        var didDisappear = false
        recorder.onEvent = { event in
            let matches: Bool = switch event {
            case .willTransition: callback == 0
            case .didFinishTransition(_, completed: true): callback == 1
            case .didSelect("b"): callback == 2
            default: false
            }
            guard matches, !didDisappear else { return }
            didDisappear = true
            pager.beginAppearanceTransition(false, animated: false)
            pager.endAppearanceTransition()
        }
        pager.delegate = recorder
        pager.selectPage("b", animated: false)
        #expect(didDisappear)
        #expect(!pager.isTransitioning)
        #expect(a.events.last == "didDisappear")
        if callback == 0 {
            #expect(pager.selectedPageId == "a")
            #expect(b.events == ["willAppear", "willDisappear", "didDisappear"])
        } else {
            #expect(b.events == ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        }
        recorder.onEvent = nil
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        #expect((pager.currentViewController as? HandoffLifecyclePage)?.events.suffix(2) == ["willAppear", "didAppear"])
    }

    @Test("Reusing a retained page in a new composite is not overwritten by old asynchronous cleanup")
    func immediatePageReuse() async throws {
        let page = HandoffScrollPage()
        let originalInset = UIEdgeInsets(top: 12, left: 3, bottom: 18, right: 4)
        page.scroll.contentInset = originalInset
        weak var oldWrapper: StickyPagerViewController<PagerTabBar>?
        autoreleasepool {
            let first = singleSticky(page: page)
            oldWrapper = first
            layout(first)
        }
        try #require(oldWrapper == nil)
        try #require(page.parent == nil)
        let second = singleSticky(page: page)
        second.setHeaderHeight(350)
        layout(second)
        #expect(page.scroll.contentInset.top == 406)
        #expect(page.scroll.contentOffset.y == -406)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(page.scroll.contentInset.top == 406)
        #expect(page.scroll.contentInsetAdjustmentBehavior == .never)
        #expect(page.scroll.alwaysBounceVertical)
        #expect(page.scroll.contentOffset.y == -406)
        #expect(second.pager.currentViewController === page)
        #expect(second.headerView.superview?.superview === page.scroll)
        second.setPages([], items: [])
        #expect(page.scroll.contentInset == originalInset)
        #expect(page.scroll.contentInsetAdjustmentBehavior == .automatic)
        #expect(!page.scroll.alwaysBounceVertical)
    }

    private func makeSticky(a: HandoffScrollPage, b: HandoffScrollPage, headerHeight: CGFloat = 200) -> StickyPagerViewController<PagerTabBar> {
        StickyPagerViewController(
            pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }],
            items: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
            headerView: UIView(), headerHeight: headerHeight,
            scrollViewProvider: { _, controller in (controller as! HandoffScrollPage).scroll }
        )
    }

    private func singleSticky(page: HandoffScrollPage) -> StickyPagerViewController<PagerTabBar> {
        StickyPagerViewController(
            pages: [PagerPage(id: "a") { page }], items: [.init(id: "a", title: "A")],
            headerView: UIView(), headerHeight: 200,
            scrollViewProvider: { _, controller in (controller as! HandoffScrollPage).scroll }
        )
    }

    private func layout(_ controller: UIViewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
}

@MainActor
private final class HandoffScrollPage: UIViewController {
    let scroll = UIScrollView()
    override func loadView() {
        view = scroll
        scroll.contentSize = CGSize(width: 320, height: 1800)
    }
}

@MainActor
private final class HandoffLifecyclePage: UIViewController {
    var events: [String] = []
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        events.append("willAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        events.append("didAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        events.append("willDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        events.append("didDisappear")
    }
}

@MainActor
private final class HandoffDelegate: PagerViewControllerDelegate {
    var onEvent: ((PagerEvent) -> Void)?
    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        onEvent?(event)
    }
}
