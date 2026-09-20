//
//  PagerAppearanceReentryTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Child appearance reentry and navigation resizing")
struct PagerAppearanceReentryTests {
    @Test("Child lifecycle dismissal finishes a page transition exactly once", arguments: ["willDisappear", "didDisappear", "willAppear", "didAppear"])
    func childLifecycleDismissal(callback: String) {
        let a = ReentrantPage(), b = ReentrantPage()
        let pager = PagerViewController(pages: [.init(id: "a") { a }, .init(id: "b") { b }])
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.view.layoutIfNeeded()
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        a.events = []
        let recorder = ReentrantDelegate()
        pager.delegate = recorder
        var fired = false
        let action: (String) -> Void = { event in
            guard event == callback, !fired else { return }
            fired = true
            pager.beginAppearanceTransition(false, animated: false)
            pager.endAppearanceTransition()
        }
        a.action = action
        b.action = action
        pager.selectPage("b", animated: false)
        a.action = nil
        b.action = nil
        #expect(fired)
        #expect(!pager.isTransitioning)
        #expect(a.events.last == "didDisappear")
        #expect(b.events.last == "didDisappear")
        let completes = callback.hasPrefix("did")
        #expect(recorder.completions == [completes])
        #expect(recorder.selections == (completes ? [PagerPageId("b")] : []))
        #expect(pager.selectedPageId == (completes ? "b" : "a"))
        #expect(recorder.eventOrder == (completes ? ["will", "finish", "select"] : ["will", "finish"]))
        #expect(a.events == (completes
                ? ["willDisappear", "didDisappear"]
                : ["willDisappear", "willAppear", "didAppear", "willDisappear", "didDisappear"]))
        #expect(b.events == (completes
                ? ["willAppear", "didAppear", "willDisappear", "didDisappear"]
                : ["willAppear", "willDisappear", "didDisappear"]))
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        #expect((pager.currentViewController as? ReentrantPage)?.events.suffix(2) == ["willAppear", "didAppear"])
    }

    @Test("Page replacement finishes child appearance before forwarding parent dismissal", arguments: ["willDisappear", "didDisappear", "willAppear", "didAppear"])
    func replacementLifecycleDismissal(callback: String) {
        let a = ReentrantPage(), b = ReentrantPage()
        let pager = PagerViewController(pages: [.init(id: "a") { a }])
        pager.loadViewIfNeeded()
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        a.events = []
        var fired = false
        let action: (String) -> Void = { event in
            guard event == callback, !fired else { return }
            fired = true
            pager.beginAppearanceTransition(false, animated: false)
            pager.endAppearanceTransition()
        }
        a.action = action
        b.action = action
        pager.setPages([.init(id: "b") { b }])
        a.action = nil
        b.action = nil
        #expect(fired)
        #expect(a.events == ["willDisappear", "didDisappear"])
        #expect(b.events == ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        #expect(a.parent == nil)
        #expect(pager.currentViewController === b)
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        #expect(b.events.suffix(2) == ["willAppear", "didAppear"])
    }

    @Test("Resizing reveals selection but progress updates preserve manual navigation scrolling")
    func selectedTabAfterResize() throws {
        let bar = PagerTabBar(frame: CGRect(x: 0, y: 0, width: 640, height: 44))
        bar.setItems((0 ..< 10).map { .init(id: PagerPageId("\($0)"), title: "Page \($0)") }, selectedPageId: "5")
        bar.layoutIfNeeded()
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        let selected = try #require(scroll.subviews.compactMap { $0 as? UIButton }.first { $0.tag == 5 })
        #expect(scroll.bounds.contains(selected.frame))
        bar.frame.size.width = 160
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        #expect(scroll.bounds.contains(selected.frame))
        scroll.contentOffset.x = 0
        let manualOffset = scroll.contentOffset
        bar.displayTransition(.init(source: "5", destination: "6", progress: 0.5))
        #expect(scroll.contentOffset == manualOffset)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        #expect(scroll.contentOffset == manualOffset)
    }
}

@MainActor
private final class ReentrantPage: UIViewController {
    var events: [String] = []
    var action: ((String) -> Void)?
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        events.append("willAppear")
        action?("willAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        events.append("didAppear")
        action?("didAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        events.append("willDisappear")
        action?("willDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        events.append("didDisappear")
        action?("didDisappear")
    }
}

@MainActor
private final class ReentrantDelegate: PagerViewControllerDelegate {
    var completions: [Bool] = []
    var selections: [PagerPageId] = []
    var eventOrder: [String] = []
    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        switch event {
        case .willTransition:
            eventOrder.append("will")
        case let .didFinishTransition(_, completed):
            completions.append(completed)
            eventOrder.append("finish")
        case let .didSelect(id):
            if let id { selections.append(id) }
            eventOrder.append("select")
        case .didUpdateTransition:
            break
        }
    }
}
