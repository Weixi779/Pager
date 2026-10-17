//
//  PagerInterruptedSwipeTests.swift
//  PagerTests
//
//  Created by weixi on 2026/10/13.
//  Copyright © 2026 weixi. All rights reserved.
//
@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Interrupted pager swipes")
struct PagerInterruptedSwipeTests {
    @Test("Reversing across the committed page balances appearance and commits only the final selection", arguments: [false, true], [false, true])
    func reverseAcrossSource(reverse: Bool, cancel: Bool) {
        let (pager, pages, observer) = makePager(selected: "b")
        let direction: CGFloat = reverse ? -1 : 1
        let initialDestination = reverse ? 0 : 2
        let finalDestination = reverse ? 2 : 0
        scroll(pager, 1 + direction * 0.75)
        resumeDragging(pager)
        #expect(pages[1].events == ["willDisappear"])
        #expect(pages[initialDestination].events == ["willAppear"])
        for distance: CGFloat in [0.5, 0.1, -0.1, -0.5, -0.75] {
            scroll(pager, 1 + direction * distance)
            #expect(pager.selectedPageId == "b")
            #expect(observer.commits.isEmpty)
        }
        #expect(pages[initialDestination].events == ["willAppear", "willDisappear", "didDisappear"])
        resumeDragging(pager)
        scroll(pager, cancel ? 1 : CGFloat(finalDestination))
        pager.host.scrollViewDidEndDecelerating(pager.host.scrollView)
        let expected: PagerPageId = cancel ? "b" : (reverse ? "c" : "a")
        #expect(pager.selectedPageId == expected)
        #expect(observer.commits == (cancel ? [] : [expected]))
        #expect(observer.selections == (cancel ? [] : [expected]))
        #expect(!pager.isTransitioning)
        for (index, page) in pages.enumerated() {
            let isSelected = index == (cancel ? 1 : finalDestination)
            #expect(page.events.last == (isSelected ? "didAppear" : "didDisappear"))
            #expect(page.view.accessibilityElementsHidden == !isSelected)
        }
    }

    @Test("Parent disappearance or resizing cancels resumed swipes and restores the committed page", arguments: [false, true], [false, true])
    func cancelResumedSwipe(reverse: Bool, resize: Bool) {
        let (pager, pages, observer) = makePager(selected: reverse ? "c" : "a")
        let origin: CGFloat = reverse ? 2 : 0
        let direction: CGFloat = reverse ? -1 : 1
        for distance: CGFloat in [0.75, 1.25, 1.75, 1.1, 0.6] {
            scroll(pager, origin + direction * distance)
            resumeDragging(pager)
        }
        if resize {
            pager.view.frame.size.width = 500
            pager.view.setNeedsLayout()
            pager.view.layoutIfNeeded()
        } else {
            pager.beginAppearanceTransition(false, animated: false)
            pager.endAppearanceTransition()
        }
        #expect(!pager.isTransitioning)
        #expect(observer.commits.isEmpty)
        #expect(observer.selections.isEmpty)
        #expect(pager.host.position == origin)
        for (index, page) in pages.enumerated() {
            #expect(page.events.last == (resize && CGFloat(index) == origin ? "didAppear" : "didDisappear"))
        }
        if !resize {
            pager.beginAppearanceTransition(true, animated: false)
            pager.endAppearanceTransition()
            #expect(pages[Int(origin)].events.suffix(2) == ["willAppear", "didAppear"])
        }
    }

    @Test("A drag taking over animated selection completes or cancels appearance exactly once", arguments: [false, true], [false, true])
    func interruptAnimatedSelection(reverse: Bool, cancel: Bool) {
        let source: PagerPageId = reverse ? "c" : "a"
        let (pager, pages, observer) = makePager(selected: source)
        let origin: CGFloat = reverse ? 2 : 0
        let direction: CGFloat = reverse ? -1 : 1
        pager.selectPage("b", animated: true)
        scroll(pager, origin + direction * 0.5)
        resumeDragging(pager)
        scroll(pager, cancel ? origin : 1)
        pager.host.scrollViewDidEndDragging(pager.host.scrollView, willDecelerate: false)
        #expect(pager.selectedPageId == (cancel ? source : "b"))
        #expect(observer.commits == (cancel ? [] : ["b"]))
        #expect(observer.selections == (cancel ? [] : ["b"]))
        #expect(pages[Int(origin)].events == (cancel ? ["willDisappear", "willAppear", "didAppear"] : ["willDisappear", "didDisappear"]))
        #expect(pages[1].events == (cancel ? ["willAppear", "willDisappear", "didDisappear"] : ["willAppear", "didAppear"]))
        #expect(!pager.isTransitioning)
    }

    @Test("Navigation emphasis follows visible position through repeated reversals", arguments: [false, true])
    func navigationMatchesPositionThroughReversals(reverse: Bool) {
        let (pager, _, _) = makePager(selected: reverse ? "c" : "a")
        let navigation = NavigationView()
        navigation.setSelection(pager.selectedPageId)
        pager.onEvent = { navigation.receive($0) }
        let positions: [CGFloat] = [0.2, 0.8, 1, 1.01, 1.6, 1.99, 1.1, 1, 0.99, 0.4, 0.05, 0.7, 1.5, 2]
        for position in positions {
            let targetPosition = reverse ? 2 - position : position
            scroll(pager, targetPosition)
            let emphasisBeforeDragging = navigation.weights
            resumeDragging(pager)
            #expect(navigation.weights == emphasisBeforeDragging)
            for index in navigation.pageIds.indices {
                // UIScrollView aligns content offsets to physical pixels.
                let expected = max(0, 1 - abs(pager.host.position - CGFloat(index)))
                #expect(abs(navigation.weights[index] - expected) < 0.00001, "position=\(pager.host.position) index=\(index) actual=\(navigation.weights[index]) expected=\(expected)")
            }
        }
        pager.host.scrollViewDidEndDecelerating(pager.host.scrollView)
        #expect(pager.selectedPageId == (reverse ? "a" : "c"))
    }

    private func makePager(selected: PagerPageId) -> (PagerViewController, [LifecyclePage], EventRecorder) {
        let pages = (0 ..< 3).map { _ in LifecyclePage() }
        let ids: [PagerPageId] = ["a", "b", "c"]
        let pager = PagerViewController(pages: ids.enumerated().map { index, id in .init(id: id) { pages[index] } }, selectedPageId: selected)
        let observer = EventRecorder()
        pager.delegate = observer
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.view.setNeedsLayout()
        pager.view.layoutIfNeeded()
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        pages.forEach { $0.events = [] }
        return (pager, pages, observer)
    }

    private func scroll(_ pager: PagerViewController, _ position: CGFloat) {
        pager.host.scrollView.contentOffset.x = position * 320
    }

    private func resumeDragging(_ pager: PagerViewController) {
        pager.host.scrollViewDidEndDragging(pager.host.scrollView, willDecelerate: true)
        pager.host.scrollViewWillBeginDragging(pager.host.scrollView)
    }
}

@MainActor
private final class LifecyclePage: UIViewController {
    var events: [String] = []
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); events.append("willAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); events.append("didAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); events.append("willDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); events.append("didDisappear")
    }
}

@MainActor
private final class EventRecorder: PagerViewControllerDelegate {
    var commits: [PagerPageId] = []
    var selections: [PagerPageId?] = []
    func pager(_: any PagerControlling, didCommit transition: PagerTransition) {
        commits.append(transition.destination)
    }

    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        if case let .didSelect(id) = event { selections.append(id) }
    }
}

@MainActor
private final class NavigationView: UIView, PagerNavigationPresenting {
    var pageIds: [PagerPageId] = ["a", "b", "c"]
    var onSelect: ((PagerPageId) -> Void)?
    var weights: [CGFloat] = [0, 0, 0]
    func setSelection(_ id: PagerPageId?) {
        weights = pageIds.map { $0 == id ? 1 : 0 }
    }

    func displayTransition(_ transition: PagerTransition) {
        weights = pageIds.map { $0 == transition.source ? 1 - transition.progress : ($0 == transition.destination ? transition.progress : 0) }
    }
}
