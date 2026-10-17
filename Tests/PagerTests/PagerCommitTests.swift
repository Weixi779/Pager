//
//  PagerCommitTests.swift
//  PagerTests
//
//  Created by weixi on 2026/10/12.
//

@testable import Pager
import Testing
import UIKit

@MainActor
struct PagerCommitTests {
    @Test("Commit precedes destination exposure; completion still follows appearance", arguments: [true, false])
    func commitOrder(completed: Bool) {
        let recorder = CommitRecorder()
        let source = CommitPage(), target = CommitPage()
        let pager = PagerViewController(pages: [.init(id: "a") { source }, .init(id: "b") { target }])
        pager.delegate = recorder
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        pager.view.layoutIfNeeded()
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        source.onDisappear = { recorder.events.append("source.disappear") }
        source.onAppear = { recorder.events.append("source.appear") }
        target.onAppear = { recorder.events.append("target.appear") }
        target.onDisappear = { recorder.events.append("target.disappear") }
        pager.host.scrollView.contentOffset.x = 120
        pager.host.scrollView.contentOffset.x = completed ? 320 : 0
        pager.host.scrollViewDidEndDragging(pager.host.scrollView, willDecelerate: false)
        #expect(recorder.events == (
            completed
                ? ["source.disappear", "commit.b", "target.appear", "finish.true", "select"]
                : ["source.appear", "target.disappear", "finish.false"]
        ))
    }

    @Test("A selection requested during commit waits for the existing completion")
    func commitReentry() async {
        let recorder = CommitRecorder()
        let pager = PagerViewController(pages: ["a", "b", "c"].map { id in
            .init(id: PagerPageId(id)) { UIViewController() }
        })
        pager.delegate = recorder
        recorder.onCommit = { if $0.destination == "b" { pager.selectPage("c", animated: false) } }
        pager.selectPage("b", animated: false)
        #expect(recorder.events == ["commit.b", "finish.true", "select"])
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(pager.selectedPageId == "c")
        #expect(recorder.events == ["commit.b", "finish.true", "select", "commit.c", "finish.true", "select"])
    }
}

@MainActor
private final class CommitRecorder: PagerViewControllerDelegate {
    var events: [String] = []
    var onCommit: ((PagerTransition) -> Void)?
    func pager(_ pager: any PagerControlling, didCommit transition: PagerTransition) {
        #expect(pager.selectedPageId == transition.destination)
        events.append("commit.\(transition.destination.rawValue)")
        onCommit?(transition)
    }

    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        switch event {
        case let .didFinishTransition(_, completed): events.append("finish.\(completed)")
        case .didSelect: events.append("select")
        default: break
        }
    }
}

@MainActor
private final class CommitPage: UIViewController {
    var onAppear: (() -> Void)?
    var onDisappear: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear?()
    }
}
