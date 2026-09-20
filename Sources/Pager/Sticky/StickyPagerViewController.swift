//
//  StickyPagerViewController.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// Combines shared header, tabs and native vertically scrolling pages.
/// Each provider result must fill its page's viewport, with no independently
/// scrolling ancestor. Configure UIRefreshControl on that list in the feature.
@MainActor
public final class StickyPagerViewController: UIViewController {
    public let pager: PagerViewController
    public let tabBar = PagerTabBar()
    public let headerView: UIView
    public private(set) var headerHeight: CGFloat
    public private(set) var tabBarHeight: CGFloat

    private let viewport = UIView()
    private let chrome = UIView()
    private let scrollViewProvider: (PagerPageID, UIViewController) -> UIScrollView
    private var coordinator: StickyScrollCoordinator?
    private var baseInsets: [PagerPageID: UIEdgeInsets] = [:]

    public init(pages: [PagerPage], items: [PagerTabBar.Item], headerView: UIView,
                headerHeight: CGFloat, tabBarHeight: CGFloat = 44,
                selectedPageID: PagerPageID? = nil,
                scrollViewProvider: @escaping (PagerPageID, UIViewController) -> UIScrollView) throws {
        guard pages.map(\.id) == items.map(\.id) else { throw PagerError.tabItemsDoNotMatchPages }
        precondition(headerHeight.isFinite && headerHeight >= 0 && tabBarHeight.isFinite && tabBarHeight >= 0)
        pager = try PagerViewController(pages: pages, selectedPageID: selectedPageID)
        self.headerView = headerView
        self.headerHeight = headerHeight
        self.tabBarHeight = tabBarHeight
        self.scrollViewProvider = scrollViewProvider
        super.init(nibName: nil, bundle: nil)
        try tabBar.setItems(items, selectedPageID: pager.selectedPageID)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        viewport.clipsToBounds = true
        view.addSubview(viewport)
        chrome.addSubview(headerView)
        chrome.addSubview(tabBar)
        coordinator = StickyScrollCoordinator(chrome: chrome, overlay: viewport,
                                              headerHeight: headerHeight, tabBarHeight: tabBarHeight)
        pager.onPreparePage = { [weak self] id, controller in
            guard let self else { return }
            let scrollView = scrollViewProvider(id, controller)
            precondition(scrollView === controller.view || scrollView.isDescendant(of: controller.view),
                         "The primary scroll view must belong to the page controller.")
            coordinator?.attach(scrollView, id: id)
            if let inset = baseInsets[id] { coordinator?.setBaseInset(inset, for: id) }
        }
        pager.onRemovePage = { [weak self] id in self?.coordinator?.detach(id) }
        pager.onEvent = { [weak self] event in self?.receive(event) }
        tabBar.onSelect = { [weak self] id in self?.pager.selectPage(id) }
        addChild(pager)
        viewport.addSubview(pager.view)
        pager.didMove(toParent: self)
        coordinator?.activate(pager.selectedPageID)
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The composite owns safe-area placement; child lists use explicit insets.
        viewport.frame = view.safeAreaLayoutGuide.layoutFrame
        pager.view.frame = viewport.bounds
        pager.view.setNeedsLayout()
        pager.view.layoutIfNeeded()
        headerView.frame = CGRect(x: 0, y: 0, width: pager.view.bounds.width, height: headerHeight)
        tabBar.frame = CGRect(x: 0, y: headerHeight, width: pager.view.bounds.width, height: tabBarHeight)
        coordinator?.layout()
    }

    /// Heights are explicit; update after measuring dynamic header content.
    public func setHeaderHeight(_ height: CGFloat, tabBarHeight: CGFloat? = nil) {
        let tabs = tabBarHeight ?? self.tabBarHeight
        precondition(height.isFinite && height >= 0 && tabs.isFinite && tabs >= 0)
        headerHeight = height
        self.tabBarHeight = tabs
        coordinator?.updateGeometry(headerHeight: height, tabBarHeight: tabs)
        viewIfLoaded?.setNeedsLayout()
    }

    /// Change business padding through this method while attached. The coordinator
    /// owns its additional top/bottom space; native refresh inset remains separate.
    public func setContentInset(_ inset: UIEdgeInsets, for id: PagerPageID) {
        guard pager.pageIDs.contains(id) else { return }
        baseInsets[id] = inset
        coordinator?.setBaseInset(inset, for: id)
    }

    /// Replace pages and tab items together. Prefer this to calling pager.setPages
    /// directly on a composite, which cannot update its navigation items atomically.
    public func setPages(_ pages: [PagerPage], items: [PagerTabBar.Item], selectedPageID: PagerPageID? = nil) throws {
        guard pages.map(\.id) == items.map(\.id) else { throw PagerError.tabItemsDoNotMatchPages }
        try pager.setPages(pages, selectedPageID: selectedPageID)
        try tabBar.setItems(items, selectedPageID: pager.selectedPageID)
        baseInsets = baseInsets.filter { pager.pageIDs.contains($0.key) }
        coordinator?.activate(pager.selectedPageID)
        viewIfLoaded?.setNeedsLayout()
    }

    override public var childForStatusBarStyle: UIViewController? {
        pager
    }

    override public var childForStatusBarHidden: UIViewController? {
        pager
    }

    private func receive(_ event: PagerEvent) {
        tabBar.receive(event)
        switch event {
        case let .willTransition(transition): coordinator?.beginTransition(to: transition.destination)
        case let .didFinishTransition(transition, completed):
            coordinator?.activate(completed ? transition.destination : transition.source)
        case let .didSelect(id): coordinator?.activate(id)
        case .didUpdateTransition: break
        }
    }
}
