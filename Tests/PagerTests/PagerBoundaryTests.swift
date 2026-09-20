//
//  PagerBoundaryTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Pager boundary regressions")
struct PagerBoundaryTests {
    @Test("Preparing the public pager before its wrapper still attaches every retained page", arguments: [false, true])
    func selectionBeforeWrapperLoad(selectEarly: Bool) {
        let a = BoundaryListPage(), b = BoundaryListPage()
        var creations: [PagerPageId] = []
        var connections: [PagerPageId] = []
        let sticky = StickyPagerViewController(
            pages: [PagerPage(id: "a") { creations.append("a"); return a },
                    PagerPage(id: "b") { creations.append("b"); return b }],
            items: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
            headerView: UIView(),
            headerHeight: 200,
            scrollViewProvider: { id, controller in
                connections.append(id)
                return (controller as! BoundaryListPage).scroll
            }
        )
        sticky.setContentInset(UIEdgeInsets(
            top: 12,
            left: 0,
            bottom: 0,
            right: 0
        ), for: "a")
        (sticky.pager as! PagerViewController).loadViewIfNeeded()
        if selectEarly { #expect(sticky.pager.selectPage("b", animated: false)) }
        #expect(!sticky.isViewLoaded)
        layout(sticky)
        #expect(sticky.tabBar.selectedPageId == (selectEarly ? "b" : "a"))
        #expect(a.scroll.contentInset.top == 256)
        sticky.pager.selectPage("b", animated: false)
        #expect(b.scroll.contentInset.top == 244)
        #expect(sticky.headerView.superview?.superview === b.scroll)
        sticky.pager.selectPage("a", animated: false)
        #expect(a.scroll.contentInset.top == 256)
        #expect(sticky.headerView.superview?.superview === a.scroll)
        #expect(creations == ["a", "b"])
        #expect(connections == ["a", "b"])
    }

    @Test("Initial selection is revealed once bounds become usable", arguments: [false, true])
    func initialSelectedTabVisibility(initiallyZeroSized: Bool) throws {
        let frame = CGRect(
            x: 0,
            y: 0,
            width: 160,
            height: 44
        )
        let bar = PagerTabBar(frame: initiallyZeroSized ? .zero : frame)
        let items = (0 ..< 10).map { PagerTabBar.Item(id: PagerPageId("\($0)"), title: "Page \($0)") }
        bar.setItems(items, selectedPageId: "9")
        bar.layoutIfNeeded()
        bar.frame = frame
        bar.layoutIfNeeded()
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        let selected = try #require(scroll.subviews.compactMap { $0 as? UIButton }.first { $0.tag == 9 })
        #expect(scroll.bounds.contains(selected.frame))
    }

    @Test("Composite replacement publishes coherent tabs including empty and unloaded states", arguments: [false, true], [false, true])
    func coherentReplacementCallback(loaded: Bool, empty: Bool) {
        let a = BoundaryListPage(), b = BoundaryListPage()
        let sticky = makeSticky(a: a, b: b)
        if loaded { layout(sticky) }
        let recorder = BoundaryDelegate()
        sticky.pager.delegate = recorder
        var received = false
        recorder.onSelect = { id in
            received = true
            #expect(sticky.tabBar.items.map(\.id) == sticky.pager.pageIds)
            #expect(sticky.tabBar.selectedPageId == id)
        }
        sticky.setPages(
            empty ? [] : [PagerPage(id: "c") { BoundaryListPage() }],
            items: empty ? [] : [.init(id: "c", title: "C")]
        )
        #expect(received)
        #expect(sticky.tabBar.selectedPageId == (empty ? nil : "c"))
    }

    @Test("Replacing tab items retains visibility of a distant selected tab")
    func replacementSelectedTabVisibility() throws {
        let bar = PagerTabBar(frame: CGRect(
            x: 0,
            y: 0,
            width: 160,
            height: 44
        ))
        let items = (0 ..< 10).map { PagerTabBar.Item(id: PagerPageId("\($0)"), title: "Page \($0)") }
        bar.setItems(items, selectedPageId: "0")
        bar.layoutIfNeeded()
        bar.setSelection("9")
        bar.setItems(items.reversed(), selectedPageId: "9")
        bar.layoutIfNeeded()
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        let selected = try #require(scroll.subviews.compactMap { $0 as? UIButton }.first { $0.tag == 0 })
        #expect(scroll.bounds.contains(selected.frame))
    }

    @Test("Indicator updates do not undo the user's manual tab scrolling")
    func transitionPreservesTabScroll() throws {
        let bar = PagerTabBar(frame: CGRect(
            x: 0,
            y: 0,
            width: 160,
            height: 44
        ))
        let items = (0 ..< 10).map { PagerTabBar.Item(id: PagerPageId("\($0)"), title: "Page \($0)") }
        bar.setItems(items, selectedPageId: "9")
        bar.layoutIfNeeded()
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        scroll.contentOffset.x = 100
        bar.displayTransition(PagerTransition(
            source: "9",
            destination: "8",
            progress: 0.5
        ))
        #expect(scroll.contentOffset.x == 100)
    }

    @Test("Rejected composite replacements leave both pages and tab items unchanged")
    func failedReplacementIsAtomic() {
        let sticky = makeSticky(a: BoundaryListPage(), b: BoundaryListPage())
        layout(sticky)
        let original = sticky.tabBar.items
        #expect(!sticky.setPages(
            [PagerPage(id: "c") { BoundaryListPage() }, PagerPage(id: "c") { BoundaryListPage() }],
            items: [.init(id: "c", title: "C"), .init(id: "c", title: "C")]
        ))
        #expect(!sticky.setPages(
            [PagerPage(id: "c") { BoundaryListPage() }],
            items: [.init(id: "c", title: "C")],
            selectedPageId: "missing"
        ))
        #expect(!sticky.setPages([], items: [.init(id: "c", title: "C")]))
        (sticky.pager as! PagerViewController).host.scrollView.contentOffset.x = 120
        #expect(sticky.pager.isTransitioning)
        #expect(!sticky.setPages([], items: []))
        #expect(sticky.pager.pageIds == ["a", "b"])
        #expect(sticky.pager.selectedPageId == "a")
        #expect(sticky.tabBar.items == original)
        #expect(sticky.tabBar.selectedPageId == "a")
    }

    @Test("Composite callbacks reject replacement and preserve deferred selection revision", arguments: [false, true])
    func replacementReentrancy(newerSelection: Bool) async {
        let sticky = makeSticky(a: BoundaryListPage(), b: BoundaryListPage())
        layout(sticky)
        let recorder = BoundaryDelegate()
        sticky.pager.delegate = recorder
        var received = false
        recorder.onSelect = { id in
            #expect(sticky.tabBar.items.map(\.id) == sticky.pager.pageIds)
            #expect(sticky.tabBar.selectedPageId == id)
            guard id == "c" else { return }
            received = true
            #expect(!sticky.setPages([], items: []))
            #expect(sticky.pager.selectPage("d", animated: false))
            #expect(sticky.pager.selectedPageId == "c")
        }
        sticky.setPages(
            ["c", "d", "e"].map { id in PagerPage(id: PagerPageId(id)) { BoundaryListPage() } },
            items: ["c", "d", "e"].map { .init(id: PagerPageId($0), title: $0) }
        )
        #expect(received)
        if newerSelection { sticky.pager.selectPage("e", animated: false) }
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(sticky.pager.selectedPageId == (newerSelection ? "e" : "d"))
        #expect(sticky.tabBar.selectedPageId == sticky.pager.selectedPageId)
    }

    private func makeSticky(a: BoundaryListPage, b: BoundaryListPage) -> StickyPagerViewController<PagerTabBar> {
        StickyPagerViewController(
            pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }],
            items: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
            headerView: UIView(),
            headerHeight: 200,
            scrollViewProvider: { _, controller in (controller as! BoundaryListPage).scroll }
        )
    }

    private func layout(_ controller: UIViewController) {
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
}

@MainActor
private final class BoundaryListPage: UIViewController {
    let scroll = UIScrollView()
    override func loadView() {
        view = scroll
        scroll.contentSize = CGSize(width: 320, height: 1500)
    }
}

@MainActor
private final class BoundaryDelegate: PagerViewControllerDelegate {
    var onSelect: ((PagerPageId?) -> Void)?
    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        if case let .didSelect(id) = event { onSelect?(id) }
    }
}
