//
//  PagerNativeIntegrationTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Native list and status bar integration")
struct PagerNativeIntegrationTests {
    @Test("Native refresh control occupies the gap below navigation", arguments: [0, 1, 2])
    func refreshBelowNavigation(listKind: Int) throws {
        let scroll: UIScrollView = switch listKind {
        case 1: UITableView(frame: .zero, style: .plain)
        case 2: UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        default: UIScrollView()
        }
        let page = UIViewController()
        page.view = scroll
        let otherPage = UIViewController()
        let otherScroll = UIScrollView()
        otherPage.view = otherScroll
        let refresh = UIRefreshControl()
        scroll.refreshControl = refresh
        let sticky = StickyPagerViewController(
            pages: [.init(id: "a") { page }, .init(id: "b") { otherPage }],
            items: [.init(id: "a", title: "A"), .init(id: "b", title: "B")],
            headerView: UIView(), headerHeight: 200,
            scrollViewProvider: { id, _ in id == "a" ? scroll : otherScroll }
        )
        sticky.loadViewIfNeeded()
        sticky.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let window = UIWindow(frame: sticky.view.frame)
        window.addSubview(sticky.view)
        window.isHidden = false
        defer { window.isHidden = true }
        sticky.view.layoutIfNeeded()
        let viewport = try #require(scroll.superview)
        let originalHeader = sticky.headerView.convert(sticky.headerView.bounds, to: viewport)
        let originalBar = sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport)
        let restingOffset = scroll.contentOffset.y
        scroll.contentOffset.y = restingOffset - 80
        UIView.performWithoutAnimation {
            refresh.beginRefreshing()
            scroll.layoutIfNeeded()
        }
        #expect(refresh.isRefreshing)
        #expect(sticky.headerView.convert(sticky.headerView.bounds, to: viewport) == originalHeader)
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport) == originalBar)
        let refreshFrame = refresh.convert(refresh.bounds, to: viewport)
        #expect(refreshFrame.height > 0)
        #expect(refreshFrame.minY >= originalBar.maxY - 0.5)
        #expect(refreshFrame.maxY <= scroll.convert(.zero, to: viewport).y + 0.5)
        sticky.pager.selectPage("b", animated: false)
        sticky.pager.selectPage("a", animated: false)
        #expect(refresh.isRefreshing)
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport) == originalBar)
        UIView.performWithoutAnimation {
            refresh.endRefreshing()
            scroll.contentOffset.y = restingOffset
            scroll.layoutIfNeeded()
        }
        #expect(!refresh.isRefreshing)
        #expect(sticky.tabBar.convert(sticky.tabBar.bounds, to: viewport) == originalBar)
        #expect(scroll.contentInset.top == -restingOffset)
    }

    @Test("Page replacement and clearing invalidate status bar ownership")
    func replacementInvalidatesStatusBar() throws {
        let a = NativeStatusPage(hidden: false), b = NativeStatusPage(hidden: true)
        let pages: [PagerPage] = [.init(id: "a") { a }, .init(id: "b") { b }]
        let pager = PagerViewController(pages: pages)
        pager.loadViewIfNeeded()
        pager.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let window = UIWindow(frame: pager.view.frame)
        window.rootViewController = pager
        window.isHidden = false
        defer { window.isHidden = true }
        pager.view.layoutIfNeeded()
        pager.beginAppearanceTransition(true, animated: false)
        pager.endAppearanceTransition()
        pager.selectPage("b", animated: false)
        pager.selectPage("a", animated: false)
        let selector = #selector(UIViewController.setNeedsStatusBarAppearanceUpdate)
        let method = try #require(class_getInstanceMethod(PagerViewController.self, selector))
        let original = method_getImplementation(method)
        let invoke = unsafeBitCast(original, to: (@convention(c) (UIViewController, Selector) -> Void).self)
        var invalidations = 0
        let spy: @convention(block) (UIViewController) -> Void = { receiver in
            MainActor.assumeIsolated {
                if receiver === pager { invalidations += 1 }
                invoke(receiver, selector)
            }
        }
        let spyImplementation = imp_implementationWithBlock(spy)
        let encoding = method_getTypeEncoding(method)
        // Main-actor synchronous scope: no suspension or other test can interleave
        // while this class-local spy is installed. Always restore UIKit's method.
        class_replaceMethod(PagerViewController.self, selector, spyImplementation, encoding)
        defer {
            class_replaceMethod(PagerViewController.self, selector, original, encoding)
            imp_removeBlock(spyImplementation)
        }
        pager.selectPage("b", animated: false)
        #expect(invalidations > 0)
        invalidations = 0
        pager.setPages(pages, selectedPageId: "a")
        #expect(pager.childForStatusBarStyle === a)
        #expect(pager.childForStatusBarHidden === a)
        #expect(invalidations > 0)
        invalidations = 0
        pager.setPages([])
        #expect(pager.childForStatusBarStyle == nil)
        #expect(pager.childForStatusBarHidden == nil)
        #expect(invalidations > 0)
    }

    @Test("Collection section headers pin immediately below navigation")
    func collectionSectionPinning() throws {
        let page = NativeCollectionPage()
        try checkSectionPinning(page: page, scrollView: page.collectionView) {
            let attributes = try #require(page.collectionView.collectionViewLayout.layoutAttributesForSupplementaryView(
                ofKind: UICollectionView.elementKindSectionHeader, at: IndexPath(item: 0, section: 0)
            ))
            return attributes.frame
        }
    }

    @Test("Plain table section headers pin immediately below navigation")
    func tableSectionPinning() throws {
        let page = NativeTablePage(style: .plain)
        try checkSectionPinning(page: page, scrollView: page.tableView) {
            try #require(page.tableView.headerView(forSection: 0)).frame
        }
    }

    private func checkSectionPinning(page: UIViewController, scrollView: UIScrollView,
                                     sectionFrame: () throws -> CGRect) throws {
        let sticky = StickyPagerViewController(
            pages: [.init(id: "a") { page }], items: [.init(id: "a", title: "A")],
            headerView: UIView(), headerHeight: 200, scrollViewProvider: { _, _ in scrollView }
        )
        sticky.loadViewIfNeeded()
        sticky.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        let window = UIWindow(frame: sticky.view.frame)
        window.addSubview(sticky.view)
        window.isHidden = false
        defer { window.isHidden = true }
        sticky.view.layoutIfNeeded()
        // Follow a full collapse and return to the expanded position. The original
        // fixed inset pinned native section headers 200pt below navigation.
        for offset: CGFloat in [-244, -144, -44, 300, -144, -244] {
            scrollView.contentOffset.y = offset
            scrollView.layoutIfNeeded()
            let navigationBottom = sticky.tabBar.convert(sticky.tabBar.bounds, to: (sticky.pager as! PagerViewController).view).maxY
            let headerY = try sectionFrame().minY - scrollView.contentOffset.y
            #expect(abs(headerY - navigationBottom) < 0.5)
            #expect(scrollView.contentOffset.y == offset)
            #expect(scrollView.contentInset.top == max(44, -offset))
        }
        scrollView.contentOffset.y = 300
        sticky.setHeaderHeight(350, tabBarHeight: 60)
        sticky.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        #expect(scrollView.contentOffset.y == 284)
        #expect(try abs(sectionFrame().minY - scrollView.contentOffset.y - 60) < 0.5)
        sticky.setPages([], items: [])
        scrollView.layoutIfNeeded()
        #expect(scrollView.contentInset == .zero)
        #expect(try abs(sectionFrame().minY - scrollView.contentOffset.y) < 0.5)
    }
}

@MainActor
private final class NativeStatusPage: UIViewController {
    let hidden: Bool
    init(hidden: Bool) {
        self.hidden = hidden
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var prefersStatusBarHidden: Bool {
        hidden
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        hidden ? .lightContent : .darkContent
    }
}

@MainActor
private final class NativeCollectionPage: UICollectionViewController {
    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 320, height: 60)
        layout.headerReferenceSize = CGSize(width: 320, height: 32)
        layout.sectionHeadersPinToVisibleBounds = true
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
    }

    override func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        100
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }

    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath)
    }
}

@MainActor
private final class NativeTablePage: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.sectionHeaderTopPadding = 0
        tableView.rowHeight = 60
        tableView.estimatedRowHeight = 0
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        100
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
    }

    override func tableView(_: UITableView, titleForHeaderInSection _: Int) -> String? {
        "Section"
    }

    override func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        32
    }
}
