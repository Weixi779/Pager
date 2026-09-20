//
//  PagerViewControllerTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Pager container")
struct PagerViewControllerTests {
    @Test("Factories are lazy and retained pages keep their controller and view hierarchy")
    func retainsPages() throws {
        var creations: [String] = []
        let pager = PagerViewController(pages: ["a", "b", "c"].map { name in
            PagerPage(id: PagerPageId(name)) { creations.append(name); return UIViewController() }
        })
        #expect(creations.isEmpty)
        layout(pager)
        let first = try #require(pager.currentViewController)
        let parent = first.view.superview
        #expect(creations == ["a"])
        pager.selectPage("b", animated: false)
        pager.selectPage("a", animated: false)
        #expect(creations == ["a", "b"])
        #expect(pager.currentViewController === first)
        #expect(first.parent === pager)
        #expect(first.view.superview === parent)
        #expect(pager.children.count == 2)
    }

    @Test("Distant selection does not instantiate intermediate pages")
    func distantSelection() {
        var creations: [String] = []
        let pager = PagerViewController(pages: ["a", "b", "c"].map { name in
            PagerPage(id: PagerPageId(name)) { creations.append(name); return UIViewController() }
        })
        layout(pager)
        pager.selectPage("c")
        #expect(creations == ["a", "c"])
        #expect(pager.selectedPageId == "c")
        #expect(!pager.isTransitioning)
    }

    @Test("Validation is atomic and unknown selections leave the current page unchanged")
    func validation() {
        let pager = PagerViewController(pages: pages())
        layout(pager)
        #expect(!pager.setPages([PagerPage(id: "a") { UIViewController() }, PagerPage(id: "a") { UIViewController() }]))
        #expect(!pager.setPages(pages(), selectedPageId: "missing"))
        #expect(pager.pageIds == ["a", "b"])
        #expect(!pager.selectPage("missing"))
        #expect(pager.selectedPageId == "a")
    }

    @Test("A completed switch forwards appearance exactly once to the two participating pages")
    func completedAppearance() {
        let a = LifecyclePage(), b = LifecyclePage()
        let pager = PagerViewController(pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }])
        layout(pager)
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        a.events.removeAll()
        pager.selectPage("b", animated: false)
        #expect(a.events == ["willDisappear", "didDisappear"])
        #expect(b.events == ["willAppear", "didAppear"])
        pager.beginAppearanceTransition(false, animated: false)
        pager.endAppearanceTransition()
        #expect(b.events.suffix(2) == ["willDisappear", "didDisappear"])
    }

    @Test("Interactive cancellation restores the source and balances appearance")
    func interactiveCancellation() {
        let a = LifecyclePage(), b = LifecyclePage()
        let recorder = EventRecorder()
        let pager = PagerViewController(pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }])
        pager.delegate = recorder
        layout(pager)
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        a.events.removeAll()
        pager.host.scrollView.contentOffset.x = 120
        #expect(pager.isTransitioning)
        #expect(pager.selectedPageId == "a")
        #expect(b.view.accessibilityElementsHidden)
        pager.host.scrollView.contentOffset.x = 0
        pager.host.scrollViewDidEndDragging(pager.host.scrollView, willDecelerate: false)
        #expect(!pager.isTransitioning)
        #expect(pager.selectedPageId == "a")
        #expect(a.events.last == "didAppear")
        #expect(b.events.last == "didDisappear")
        #expect(recorder.completed == [false])
        #expect(recorder.selections.isEmpty)
    }

    @Test("Interactive completion commits only after scrolling settles")
    func interactiveCompletion() {
        let pager = PagerViewController(pages: pages())
        let recorder = EventRecorder()
        pager.delegate = recorder
        layout(pager)
        pager.host.scrollView.contentOffset.x = 320
        #expect(pager.selectedPageId == "a")
        pager.host.scrollViewDidEndDecelerating(pager.host.scrollView)
        #expect(pager.selectedPageId == "b")
        #expect(recorder.completed == [true])
        #expect(recorder.selections == ["b"])
    }

    @Test("Resize cancels an unfinished transition and aligns the committed page")
    func resizeDuringTransition() {
        let pager = PagerViewController(pages: pages())
        layout(pager)
        pager.host.scrollView.contentOffset.x = 160
        pager.view.frame.size.width = 500
        pager.view.setNeedsLayout()
        pager.view.layoutIfNeeded()
        #expect(!pager.isTransitioning)
        #expect(pager.selectedPageId == "a")
        #expect(pager.host.scrollView.contentOffset.x == 0)
        #expect(pager.children.allSatisfy { $0.view.bounds.width == 500 })
    }

    @Test("Removing pages tears down containment and releases retained instances")
    func removalAndReordering() {
        let pager = PagerViewController(pages: pages())
        weak var first: UIViewController?
        // Drain UIKit's temporary references before checking ownership on iOS 16.
        let second = autoreleasepool {
            layout(pager)
            first = pager.currentViewController
            pager.selectPage("b", animated: false)
            let second = pager.currentViewController
            pager.setPages([PagerPage(id: "b") { Issue.record("Retained factory must not rerun"); return UIViewController() }])
            return second
        }
        #expect(first == nil)
        #expect(pager.currentViewController === second)
        #expect(pager.children.count == 1)
        #expect(pager.host.scrollView.contentOffset.x == 0)
        pager.setPages([])
        #expect(pager.children.isEmpty)
        #expect(pager.selectedPageId == nil)
        #expect(second?.parent == nil)
    }

    @Test("Reentrant delegate selection is applied after the current transition")
    func reentrantSelection() async {
        let pager = PagerViewController(pages: pages())
        let recorder = EventRecorder()
        pager.delegate = recorder
        recorder.onSelection = { id in
            if id == "b" { pager.selectPage("a", animated: false) }
        }
        layout(pager)
        pager.selectPage("b", animated: false)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(pager.selectedPageId == "a")
        #expect(recorder.selections == ["b", "a"])
        recorder.onSelection = nil
    }

    @Test("A hidden container does not send child appearance events on selection")
    func hiddenSelection() {
        let a = LifecyclePage(), b = LifecyclePage()
        let pager = PagerViewController(pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }])
        layout(pager)
        pager.selectPage("b", animated: false)
        #expect(a.events.isEmpty)
        #expect(b.events.isEmpty)
    }

    @Test("Parent disappearance cancels a drag before forwarding disappearance")
    func parentDisappearsDuringDrag() {
        let a = LifecyclePage(), b = LifecyclePage()
        let pager = PagerViewController(pages: [PagerPage(id: "a") { a }, PagerPage(id: "b") { b }])
        layout(pager)
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        pager.host.scrollView.contentOffset.x = 120
        pager.beginAppearanceTransition(false, animated: false)
        pager.endAppearanceTransition()
        #expect(pager.selectedPageId == "a")
        #expect(!pager.isTransitioning)
        #expect(a.events.last == "didDisappear")
        #expect(b.events.last == "didDisappear")
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        #expect(a.events.last == "didAppear")
        #expect(b.events.last == "didDisappear")
    }

    @Test("Releasing a retaining pager releases all created controllers")
    func releasesContainer() {
        weak var releasedPager: PagerViewController?
        weak var first: UIViewController?
        weak var second: UIViewController?
        // A local scope alone does not drain UIKit's autoreleased references.
        autoreleasepool {
            let pager = PagerViewController(pages: pages())
            releasedPager = pager
            layout(pager)
            first = pager.currentViewController
            pager.selectPage("b", animated: false)
            second = pager.currentViewController
        }
        #expect(releasedPager == nil)
        #expect(first == nil)
        #expect(second == nil)
    }

    @Test("An older queued request cannot override a newer explicit selection")
    func newerSelectionWins() async {
        let pager = PagerViewController(pages: pages() + [PagerPage(id: "c") { UIViewController() }])
        let recorder = EventRecorder()
        pager.delegate = recorder
        recorder.onSelection = { id in
            if id == "b" { pager.selectPage("a", animated: false) }
        }
        layout(pager)
        pager.selectPage("b", animated: false)
        pager.selectPage("c", animated: false)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(pager.selectedPageId == "c")
        #expect(recorder.selections == ["b", "c"])
        recorder.onSelection = nil
    }

    private func pages() -> [PagerPage] {
        [PagerPage(id: "a") { UIViewController() }, PagerPage(id: "b") { UIViewController() }]
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
    var completed: [Bool] = []
    var selections: [PagerPageId?] = []
    var onSelection: ((PagerPageId?) -> Void)?
    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        switch event {
        case let .didFinishTransition(_, completed): self.completed.append(completed)
        case let .didSelect(id): selections.append(id); onSelection?(id)
        default: break
        }
    }
}
