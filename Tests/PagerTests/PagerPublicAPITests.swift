//
//  PagerPublicAPITests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

import Pager
import Testing
import UIKit

@MainActor
@Suite("Public pager API")
struct PagerPublicAPITests {
    @Test("Rejected page updates preserve controllers and emit no events")
    func rejectedPages() {
        let pager = PagerViewController()
        let observer = PublicPagerObserver()
        pager.delegate = observer
        var creations = 0
        let pages = [PagerPage(id: "a") { creations += 1; return UIViewController() }]
        #expect(pager.setPages(pages))
        #expect(creations == 0)
        #expect(pager.selectPage("a"))
        #expect(creations == 1)
        let original = pager.currentViewController
        observer.selections = []
        let invalid = PagerPage(id: "b") { Issue.record("Rejected update created a page"); return UIViewController() }
        #expect(!pager.setPages([invalid, invalid]))
        #expect(!pager.setPages([invalid], selectedPageId: "missing"))
        #expect(!pager.selectPage("missing"))
        #expect(pager.pageIds == ["a"])
        #expect(pager.selectedPageId == "a")
        #expect(pager.currentViewController === original)
        #expect(creations == 1)
        #expect(observer.selections.isEmpty)
        #expect(pager.setPages([]))
        #expect(pager.currentViewController == nil)
        #expect(observer.selections.count == 1)
        #expect(observer.selections[0] == nil)
    }

    @Test("Rejected tab item updates preserve content and selection")
    func rejectedTabItems() {
        let bar = PagerTabBar()
        let original: [PagerTabBar.Item] = [.init(id: "a", title: "A"), .init(id: "b", title: "B")]
        #expect(bar.setItems(original, selectedPageId: "b"))
        bar.onSelect = { _ in Issue.record("Configuring items emitted selection intent") }
        #expect(!bar.setItems([original[0], original[0]]))
        #expect(!bar.setItems(original, selectedPageId: "missing"))
        #expect(bar.items == original)
        #expect(bar.selectedPageId == "b")
        #expect(bar.setItems([]))
        #expect(bar.pageIds.isEmpty)
        #expect(bar.selectedPageId == nil)
    }

    @Test("The public control protocol supports selection, queries and weak event subscription")
    func controlCapabilities() {
        let sticky = StickyPagerViewController(
            pages: ["a", "b"].map { id in PagerPage(id: PagerPageId(id)) {
                let controller = UIViewController()
                controller.view = UIScrollView()
                return controller
            } },
            items: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
            headerView: UIView(), headerHeight: 200,
            scrollViewProvider: { _, controller in controller.view as! UIScrollView }
        )
        sticky.loadViewIfNeeded()
        let controls: any PagerControlling = sticky.pager
        controls.isSwipeEnabled = false
        #expect(!sticky.pager.isSwipeEnabled)
        let observer = PublicPagerObserver()
        controls.delegate = observer
        #expect(controls.selectPage("b"))
        #expect(observer.selections == [PagerPageId("b")])
        #expect(controls.currentViewController != nil)
        #expect(!controls.isTransitioning)
        #expect(sticky.tabBar.selectedPageId == "b")
        autoreleasepool {
            let temporary = PublicPagerObserver()
            controls.delegate = temporary
            #expect(controls.delegate === temporary)
        }
        #expect(controls.delegate == nil)
    }
}

@MainActor
private final class PublicPagerObserver: PagerViewControllerDelegate {
    var selections: [PagerPageId?] = []
    func pager(_ pager: any PagerControlling, didReceive event: PagerEvent) {
        if case let .didSelect(id) = event {
            #expect(pager.selectedPageId == id)
            selections.append(id)
        }
    }
}
