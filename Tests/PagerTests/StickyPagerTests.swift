//
//  StickyPagerTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Sticky pager")
struct StickyPagerTests {
    @Test("Pull-down opens space below stationary chrome", arguments: [CGFloat(0), 12])
    func pullDownBelowChrome(baseTop: CGFloat) {
        let scroll = list(height: 1200)
        scroll.contentInset.top = baseTop
        let overlay = UIView(frame: scroll.bounds), chrome = UIView()
        overlay.addSubview(scroll)
        let coordinator = StickyScrollCoordinator(
            chrome: chrome,
            overlay: overlay,
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(scroll, id: "a")
        coordinator.activate("a")
        defer { coordinator.detachAll() }
        let restingOffset = scroll.contentOffset.y
        for pull: CGFloat in [0, 20, 80, 160, 80, 0] {
            scroll.contentOffset.y = restingOffset - pull
            let frame = chrome.convert(chrome.bounds, to: overlay)
            #expect(frame.minY == 0)
            #expect(frame.maxY == 244)
            #expect(coordinator.sharedCollapse == 0)
            #expect(-scroll.contentOffset.y - frame.maxY == baseTop + pull)
        }
        scroll.contentOffset.y = restingOffset - 80
        coordinator.updateGeometry(headerHeight: 300, tabBarHeight: 50)
        #expect(chrome.convert(chrome.bounds, to: overlay).minY == 0)
        #expect(-scroll.contentOffset.y - chrome.bounds.height == baseTop + 80)
    }

    @Test("Header and list share one continuous vertical offset")
    func continuousGeometry() {
        let scroll = list(height: 1200)
        let chrome = UIView(), overlay = UIView(frame: scroll.bounds)
        let coordinator = StickyScrollCoordinator(
            chrome: chrome,
            overlay: overlay,
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(scroll, id: "a")
        coordinator.activate("a")
        #expect(scroll.contentInset.top == 244)
        #expect(scroll.contentOffset.y == -244)
        #expect(chrome.superview === scroll)
        scroll.contentOffset.y = -144
        #expect(coordinator.sharedCollapse == 100)
        #expect(chrome.frame.minY - scroll.contentOffset.y == -100)
        scroll.contentOffset.y = 90
        #expect(coordinator.sharedCollapse == 200)
        #expect(chrome.frame.minY - scroll.contentOffset.y == -200)
        coordinator.detachAll()
    }

    @Test("Short and empty lists can reach the pinned position without changing content size", arguments: [CGFloat(0), 80, 400])
    func shortLists(_ contentHeight: CGFloat) {
        let scroll = list(height: contentHeight)
        let coordinator = StickyScrollCoordinator(
            chrome: UIView(),
            overlay: UIView(),
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(scroll, id: "a")
        coordinator.activate("a")
        #expect(scroll.contentSize.height == contentHeight)
        let maximum = scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height
        #expect(maximum + scroll.contentInset.top >= 200)
        coordinator.detachAll()
    }

    @Test("Horizontal transitions keep chrome in the overlay and restore it on activation")
    func horizontalTransition() {
        let a = list(height: 1600), b = list(height: 1600)
        let overlay = UIView(frame: a.bounds), chrome = UIView()
        overlay.addSubview(a)
        let coordinator = StickyScrollCoordinator(
            chrome: chrome,
            overlay: overlay,
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(a, id: "a"); coordinator.attach(b, id: "b")
        coordinator.activate("a")
        a.contentOffset.y = -144
        a.frame.origin.x = -24 // Horizontal scrolling moved the source before its callback.
        coordinator.beginTransition(to: "b")
        #expect(chrome.superview === overlay)
        #expect(chrome.frame.minX == 0)
        #expect(chrome.frame.minY == -100)
        #expect(b.contentOffset.y == -144)
        coordinator.activate("b")
        #expect(chrome.superview === b)
        #expect(b.scrollsToTop)
        #expect(!a.scrollsToTop)
        coordinator.detachAll()
    }

    @Test("Pinned switching preserves reading; expanded switching aligns the shared header")
    func readingPosition() {
        let a = list(height: 1600), b = list(height: 1600)
        let coordinator = StickyScrollCoordinator(
            chrome: UIView(),
            overlay: UIView(),
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(a, id: "a"); coordinator.attach(b, id: "b")
        coordinator.activate("a")
        a.contentOffset.y = 500
        coordinator.activate("b")
        b.contentOffset.y = 100
        coordinator.activate("a")
        #expect(a.contentOffset.y == 500)
        a.contentOffset.y = -244
        coordinator.activate("b")
        #expect(b.contentOffset.y == -244)
        coordinator.detachAll()
    }

    @Test("Native refresh inset and feature inset survive geometry changes and detach")
    func insetOwnership() {
        let scroll = list(height: 1200)
        scroll.contentInset = UIEdgeInsets(
            top: 12,
            left: 3,
            bottom: 18,
            right: 4
        )
        let coordinator = StickyScrollCoordinator(
            chrome: UIView(),
            overlay: UIView(),
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(scroll, id: "a")
        coordinator.activate("a")
        scroll.contentInset.top += 60 // Native refresh control's temporary contribution.
        coordinator.updateGeometry(headerHeight: 100, tabBarHeight: 44)
        #expect(scroll.contentInset.top == 216)
        coordinator.setBaseInset(UIEdgeInsets(
            top: 20,
            left: 5,
            bottom: 25,
            right: 6
        ), for: "a")
        #expect(scroll.contentInset.top == 224)
        coordinator.detach("a")
        #expect(scroll.contentInset == UIEdgeInsets(
            top: 80,
            left: 5,
            bottom: 25,
            right: 6
        ))
        #expect(scroll.contentInsetAdjustmentBehavior == .automatic)
        #expect(!scroll.alwaysBounceVertical)
    }

    @Test("Header resizing preserves content reading distance after pinning")
    func headerResize() {
        let scroll = list(height: 1500)
        let coordinator = StickyScrollCoordinator(
            chrome: UIView(),
            overlay: UIView(),
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(scroll, id: "a"); coordinator.activate("a")
        scroll.contentOffset.y = 300
        coordinator.updateGeometry(headerHeight: 350, tabBarHeight: 44)
        #expect(scroll.contentOffset.y == 300)
        #expect(coordinator.sharedCollapse == 350)
        coordinator.detachAll()
    }

    @Test("Releasing the coordinator clears observations and restores attached lists")
    func releaseCleanup() async {
        let scroll = list(height: 1500)
        weak var released: StickyScrollCoordinator?
        do {
            let coordinator = StickyScrollCoordinator(
                chrome: UIView(),
                overlay: UIView(),
                headerHeight: 200,
                tabBarHeight: 44
            )
            released = coordinator
            coordinator.attach(scroll, id: "a")
        }
        #expect(released == nil)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(scroll.contentInset == .zero)
        scroll.contentOffset.y = 100 // No surviving observer mutates the old chrome.
        #expect(scroll.contentOffset.y == 100)
    }

    @Test("Composite connects the active list and tab selection")
    func composite() {
        let a = ListPage(), b = ListPage()
        let sticky = StickyPagerViewController(
            pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }],
            items: [.init(id: "a", title: "精选"), .init(id: "b", title: "发现")],
            headerView: UIView(),
            headerHeight: 200,
            scrollViewProvider: { _, controller in (controller as! ListPage).scrollView }
        )
        sticky.loadViewIfNeeded()
        sticky.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        sticky.view.layoutIfNeeded()
        sticky.pager.selectPage("b", animated: false)
        #expect(sticky.tabBar.selectedPageId == "b")
        #expect(b.scrollView.contentInset.top == 244)
        #expect(a.scrollView.delegate == nil)
        sticky.setPages([], items: [])
        #expect(a.parent == nil)
        #expect(b.parent == nil)
        #expect(b.scrollView.contentInset == .zero)
    }

    @Test("Detaching a pinned list preserves the content position below the tab bar")
    func detachReadingPosition() {
        let scroll = list(height: 1600)
        scroll.contentInsetAdjustmentBehavior = .never
        let coordinator = StickyScrollCoordinator(
            chrome: UIView(),
            overlay: UIView(),
            headerHeight: 200,
            tabBarHeight: 44
        )
        coordinator.attach(scroll, id: "a")
        coordinator.activate("a")
        scroll.contentOffset.y = 300
        coordinator.detach("a")
        #expect(scroll.contentInset == .zero)
        #expect(scroll.contentOffset.y == 344)
    }

    @Test("Header state follows displayed geometry and stays frozen across paging", arguments: [true, false])
    func headerStateDuringPaging(completed: Bool) {
        let a = list(height: 1600), b = list(height: 1600)
        let overlay = UIView(frame: a.bounds), chrome = UIView()
        overlay.addSubview(a)
        overlay.addSubview(b)
        let coordinator = StickyScrollCoordinator(chrome: chrome, overlay: overlay, headerHeight: 77, tabBarHeight: 43)
        var states: [StickyPagerHeaderState] = []
        coordinator.onHeaderStateChange = { state in
            states.append(state)
            #expect(chrome.convert(chrome.bounds, to: overlay).minY == -state.collapseDistance)
        }
        coordinator.attach(a, id: "a")
        coordinator.attach(b, id: "b")
        coordinator.activate("a")
        defer { coordinator.detachAll() }
        #expect(states.last?.progress == 0)
        a.contentOffset.y = -90
        #expect(states.last?.collapseDistance == 30)
        let count = states.count
        coordinator.beginTransition(to: "b")
        b.contentOffset.y = 200
        #expect(states.count == count)
        #expect(coordinator.headerState.collapseDistance == 30)
        coordinator.activate(completed ? "b" : "a")
        #expect(coordinator.headerState.collapseDistance == 30)
        let active = completed ? b : a
        active.contentOffset.y = -43
        #expect(coordinator.headerState.progress == 1)
        active.contentOffset.y = 300
        #expect(states.last?.collapseDistance == 77)
        let pinnedCount = states.count
        active.contentOffset.y = 400
        #expect(states.count == pinnedCount)
        coordinator.updateGeometry(headerHeight: 0, tabBarHeight: 43)
        #expect(coordinator.headerState.progress == 0)
        #expect(coordinator.headerState.collapseRange == 0)
        coordinator.onHeaderStateChange = nil
    }

    @Test("Custom refresh pull-down survives switching back without a UIRefreshControl")
    func customRefreshPosition() {
        let a = list(height: 1600), b = list(height: 1600)
        let coordinator = StickyScrollCoordinator(chrome: UIView(), overlay: UIView(), headerHeight: 77, tabBarHeight: 43)
        coordinator.attach(a, id: "a")
        coordinator.attach(b, id: "b")
        coordinator.activate("a")
        defer { coordinator.detachAll() }
        a.contentInset.top += 70
        a.contentOffset.y = -190
        coordinator.activate("b")
        b.contentOffset.y = 300
        coordinator.beginTransition(to: "a")
        #expect(a.contentOffset.y == -190)
        coordinator.activate("a")
        #expect(a.contentOffset.y == -190)
        #expect(a.contentInset.top == 190)
        #expect(coordinator.headerState.collapseDistance == 0)
        // The refresh owner closes only its own space.
        a.contentInset.top -= 70
        a.contentOffset.y = -120
        #expect(coordinator.headerState.progress == 0)
    }

    @Test("Return to top uses expanded origin and preserves external inset", arguments: [CGFloat(0), 70])
    func expandedScrollToTop(externalTop: CGFloat) {
        let a = list(height: 1600)
        a.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 8, right: 0)
        let overlay = UIView(), coordinator = StickyScrollCoordinator(chrome: UIView(), overlay: overlay, headerHeight: 77, tabBarHeight: 43)
        coordinator.attach(a, id: "a")
        coordinator.activate("a")
        defer { coordinator.detachAll() }
        a.contentOffset.y = 500
        a.contentInset.top += externalTop
        #expect(coordinator.scrollToTop(of: "a", animated: false))
        #expect(a.contentOffset.y == -132 - externalTop)
        #expect(a.contentInset.top == 132 + externalTop)
        #expect(a.contentInset.bottom == 8)
        #expect(coordinator.headerState.progress == 0)
        #expect(!coordinator.scrollToTop(of: "unknown", animated: false))
        coordinator.beginTransition(to: "a")
        #expect(!coordinator.scrollToTop(of: "a", animated: false))
    }

    @Test("Public header state and return to top do not create an unloaded page")
    func publicHeaderState() {
        let a = ListPage()
        var createdB = false
        let sticky = StickyPagerViewController(
            pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { createdB = true; return ListPage() }],
            items: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
            headerView: UIView(),
            headerHeight: 77,
            tabBarHeight: 43,
            scrollViewProvider: { _, controller in (controller as! ListPage).scrollView }
        )
        #expect(sticky.headerState.collapseRange == 77)
        #expect(!sticky.scrollToTop(of: "a", animated: false))
        #expect(!sticky.isViewLoaded)
        var states: [StickyPagerHeaderState] = []
        sticky.onHeaderStateChange = { states.append($0) }
        sticky.loadViewIfNeeded()
        sticky.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        sticky.view.layoutIfNeeded()
        a.scrollView.contentOffset.y = 100
        #expect(sticky.headerState.progress == 1)
        #expect(sticky.scrollToTop(of: "a", animated: false))
        #expect(states.last?.progress == 0)
        #expect(!sticky.scrollToTop(of: "b", animated: false))
        #expect(!createdB)
        sticky.setHeaderHeight(100)
        #expect(states.last?.collapseRange == 100)
        sticky.setPages([], items: [])
        #expect(sticky.headerState.progress == 0)
    }

    private func list(height: CGFloat) -> UIScrollView {
        let view = UIScrollView(frame: CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        ))
        view.contentSize = CGSize(width: 320, height: height)
        return view
    }
}

@MainActor
private final class ListPage: UIViewController {
    let scrollView = UIScrollView()
    override func loadView() {
        view = scrollView; scrollView.contentSize = CGSize(width: 320, height: 1200)
    }
}
