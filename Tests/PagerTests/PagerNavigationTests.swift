//
//  PagerNavigationTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Injected page navigation")
struct PagerNavigationTests {
    @Test("Repeated drags during deceleration preserve navigation progress", arguments: [false, true])
    func resumedDragging(reverse: Bool) throws {
        let navigation = NavigationView()
        navigation.pageIds = ["a", "b", "c"]
        let sticky = makeSticky(navigation)
        layout(sticky)
        let pager = try #require(sticky.pager as? PagerViewController)
        let source: PagerPageId = reverse ? "c" : "a"
        pager.selectPage(source, animated: false)
        let origin: CGFloat = reverse ? 2 : 0
        let direction: CGFloat = reverse ? -1 : 1

        for progress: CGFloat in [0.25, 0.5, 0.75] {
            pager.host.scrollView.contentOffset.x = (origin + direction * progress) * 320
            pager.host.scrollViewDidEndDragging(pager.host.scrollView, willDecelerate: true)
            let expected = PagerTransition(source: source, destination: "b", progress: progress)
            #expect(navigation.transition == expected)
            let selectionUpdates = navigation.selectionUpdates

            pager.host.scrollViewWillBeginDragging(pager.host.scrollView)

            #expect(navigation.transition == expected)
            #expect(navigation.selectionUpdates == selectionUpdates)
            #expect(pager.isTransitioning)
            #expect(pager.selectedPageId == source)
        }
        pager.host.scrollView.contentOffset.x = 320
        pager.host.scrollViewDidEndDecelerating(pager.host.scrollView)
        #expect(pager.selectedPageId == "b")
        #expect(navigation.selection == "b")
        #expect(navigation.transition == nil)
    }

    @Test("Fast swipes across three pages highlight the visible neighbors", arguments: [false, true], [false, true])
    func fastSwipeAcrossPages(reverse: Bool, returnsToSource: Bool) throws {
        let navigation = NavigationView()
        navigation.pageIds = ["a", "b", "c"]
        let sticky = makeSticky(navigation)
        layout(sticky)
        let pager = try #require(sticky.pager as? PagerViewController)
        let source: PagerPageId = reverse ? "c" : "a"
        let destination: PagerPageId = reverse ? "a" : "c"
        pager.selectPage(source, animated: false)
        let delegate = NavigationDelegate()
        pager.delegate = delegate
        var selections: [PagerPageId?] = []
        delegate.onSelect = { selections.append($0) }
        let origin: CGFloat = reverse ? 2 : 0
        let direction: CGFloat = reverse ? -1 : 1

        pager.host.scrollView.contentOffset.x = (origin + direction * 0.75) * 320
        pager.host.scrollViewDidEndDragging(pager.host.scrollView, willDecelerate: true)
        pager.host.scrollViewWillBeginDragging(pager.host.scrollView)
        for distance: CGFloat in [1, 1.25, 1.75, 1.25] {
            pager.host.scrollView.contentOffset.x = (origin + direction * distance) * 320
            if distance > 1 {
                #expect(navigation.transition == PagerTransition(
                    source: "b",
                    destination: destination,
                    progress: distance - 1
                ))
            }
            #expect(pager.selectedPageId == source)
            #expect(selections.isEmpty)
        }

        if returnsToSource {
            pager.host.scrollView.contentOffset.x = (origin + direction * 0.75) * 320
            #expect(navigation.transition == PagerTransition(source: source, destination: "b", progress: 0.75))
        }
        let finalPosition = returnsToSource ? origin : origin + direction * 2
        pager.host.scrollView.contentOffset.x = finalPosition * 320
        pager.host.scrollViewDidEndDecelerating(pager.host.scrollView)
        #expect(pager.selectedPageId == (returnsToSource ? source : destination))
        #expect(navigation.selection == pager.selectedPageId)
        #expect(navigation.transition == nil)
        #expect(selections == (returnsToSource ? [] : [destination]))
    }

    @Test("Custom navigation is mounted and receives selection intent, progress and cancellation")
    func injectedNavigation() {
        let navigation = NavigationView()
        let sticky = makeSticky(navigation)
        #expect(navigation.selection == "a")
        sticky.pager.selectPage("b", animated: false)
        #expect(!sticky.isViewLoaded)
        layout(sticky)
        #expect(navigation.selection == "b")
        #expect(sticky.tabBar === navigation)
        #expect(navigation.superview === sticky.headerView.superview)
        #expect(navigation.frame == CGRect(
            x: 0,
            y: 200,
            width: 320,
            height: 44
        ))

        navigation.onSelect?("a")
        #expect(sticky.pager.selectedPageId == "a")
        #expect(navigation.selection == "a")
        (sticky.pager as! PagerViewController).host.scrollView.contentOffset.x = 160
        #expect(navigation.transition == PagerTransition(
            source: "a",
            destination: "b",
            progress: 0.5
        ))
        #expect(navigation.selection == "a")
        (sticky.pager as! PagerViewController).host.scrollView.contentOffset.x = 0
        #expect(navigation.transition == nil)
        #expect(navigation.selection == "a")
    }

    @Test("Custom contents and selection are coherent before replacement callbacks", arguments: [false, true], [false, true])
    func replacement(loaded: Bool, empty: Bool) {
        let navigation = NavigationView()
        let sticky = makeSticky(navigation)
        if loaded { layout(sticky) }
        let delegate = NavigationDelegate()
        sticky.pager.delegate = delegate
        let ids: [PagerPageId] = empty ? [] : ["c", "d"]
        var callbacks = 0
        delegate.onSelect = { id in
            callbacks += 1
            #expect(navigation.pageIds == ids)
            #expect(sticky.pager.pageIds == ids)
            #expect(navigation.selection == id)
        }
        sticky.setPages(
            pages(ids),
            navigationPageIds: ids
        ) { $0.pageIds = ids }
        #expect(callbacks == 1)
        #expect(navigation.selection == ids.first)
        #expect(sticky.tabBar === navigation)
    }

    @Test("Rejected updates never configure external navigation")
    func rejectedReplacement() {
        let navigation = NavigationView()
        let sticky = makeSticky(navigation)
        layout(sticky)
        let unexpectedUpdate: (NavigationView) -> Void = { _ in Issue.record("Rejected update configured navigation") }
        #expect(!sticky.setPages(
            pages(["c"]),
            navigationPageIds: ["d"],
            updateNavigation: unexpectedUpdate
        ))
        #expect(!sticky.setPages(
            pages(["c", "c"]),
            navigationPageIds: ["c", "c"],
            updateNavigation: unexpectedUpdate
        ))
        #expect(!sticky.setPages(
            pages(["c"]),
            navigationPageIds: ["c"],
            selectedPageId: "missing",
            updateNavigation: unexpectedUpdate
        ))
        (sticky.pager as! PagerViewController).host.scrollView.contentOffset.x = 160
        #expect(sticky.pager.isTransitioning)
        #expect(!sticky.setPages(
            [],
            navigationPageIds: [],
            updateNavigation: unexpectedUpdate
        ))
        #expect(navigation.pageIds == ["a", "b"])
        #expect(navigation.selection == "a")
        #expect(sticky.pager.pageIds == ["a", "b"])
    }

    @Test("Navigation updates run under the pager's reentrancy boundary")
    func updateReentrancy() async {
        let navigation = NavigationView()
        let sticky = makeSticky(navigation)
        layout(sticky)
        sticky.setPages(
            pages(["c", "d"]),
            navigationPageIds: ["c", "d"]
        ) { bar in
            bar.pageIds = ["c", "d"]
            #expect(!sticky.setPages(
                [],
                navigationPageIds: []
            ) { _ in Issue.record("Reentrant update ran") })
            #expect(sticky.pager.selectPage("d", animated: false))
            #expect(sticky.pager.selectedPageId == "c")
        }
        #expect(navigation.selection == "c")
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        #expect(sticky.pager.selectedPageId == "d")
        #expect(navigation.selection == "d")
    }

    @Test("The protocol extension routes events through an existential")
    func eventForwarding() {
        let navigation = NavigationView()
        let presenter: any PagerNavigationPresenting = navigation
        let transition = PagerTransition(
            source: "a",
            destination: "b",
            progress: 0.5
        )
        presenter.receive(.willTransition(transition))
        #expect(navigation.transition == transition)
        presenter.receive(.didUpdateTransition(transition))
        #expect(navigation.transition == transition)
        presenter.receive(.didFinishTransition(transition, completed: true))
        #expect(navigation.selection == "b")
        #expect(navigation.transition == nil)
        presenter.receive(.didSelect(nil))
        #expect(navigation.selection == nil)
    }

    @Test("Nonoptional initialization installs selection without creating pages")
    func initialConfiguration() {
        let navigation = NavigationView()
        var creations = 0
        let sticky = StickyPagerViewController(
            pages: ["a", "b"].map { id in
                PagerPage(id: PagerPageId(id)) { creations += 1; return NavigationPage() }
            },
            tabBar: navigation,
            headerView: UIView(),
            headerHeight: 200,
            selectedPageId: "b",
            scrollViewProvider: { _, controller in controller.view as! UIScrollView }
        )
        #expect(navigation.selection == "b")
        #expect(sticky.pager.selectedPageId == "b")
        #expect(creations == 0)
        #expect(!sticky.isViewLoaded)
    }

    private func makeSticky(_ navigation: NavigationView) -> StickyPagerViewController<NavigationView> {
        StickyPagerViewController(
            pages: pages(navigation.pageIds),
            tabBar: navigation,
            headerView: UIView(),
            headerHeight: 200,
            scrollViewProvider: { _, controller in controller.view as! UIScrollView }
        )
    }

    private func pages(_ ids: [PagerPageId]) -> [PagerPage] {
        ids.map { id in PagerPage(id: id) { NavigationPage() } }
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
private final class NavigationView: UIView, PagerNavigationPresenting {
    var pageIds: [PagerPageId] = ["a", "b"]
    var onSelect: ((PagerPageId) -> Void)?
    private(set) var selection: PagerPageId?
    private(set) var transition: PagerTransition?
    private(set) var selectionUpdates = 0

    func setSelection(_ id: PagerPageId?) {
        selectionUpdates += 1
        selection = id
        transition = nil
    }

    func displayTransition(_ transition: PagerTransition) {
        self.transition = transition
    }
}

@MainActor
private final class NavigationPage: UIViewController {
    override func loadView() {
        let scroll = UIScrollView()
        scroll.contentSize = CGSize(width: 320, height: 1500)
        view = scroll
    }
}

@MainActor
private final class NavigationDelegate: PagerViewControllerDelegate {
    var onSelect: ((PagerPageId?) -> Void)?
    func pager(_: any PagerControlling, didReceive event: PagerEvent) {
        if case let .didSelect(id) = event { onSelect?(id) }
    }
}
