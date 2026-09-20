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
public final class StickyPagerViewController<Navigation: PagerNavigationPresenting>: UIViewController {
    public var pager: any PagerControlling {
        pagerController
    }

    public let tabBar: Navigation
    public let headerView: UIView
    public private(set) var headerHeight: CGFloat
    public private(set) var tabBarHeight: CGFloat

    private let pagerController: PagerViewController
    private let viewport = UIView()
    private let chrome = UIView()
    private let scrollViewProvider: (PagerPageId, UIViewController) -> UIScrollView
    private var coordinator: StickyScrollCoordinator?
    private var baseInsets: [PagerPageId: UIEdgeInsets] = [:]

    /// Initial page identities and navigation order must match; selection must belong
    /// to those pages. Heights must be finite and nonnegative. These are caller contracts.
    public init(
        pages: [PagerPage],
        tabBar: Navigation,
        headerView: UIView,
        headerHeight: CGFloat,
        tabBarHeight: CGFloat = 44,
        selectedPageId: PagerPageId? = nil,
        scrollViewProvider: @escaping (PagerPageId, UIViewController) -> UIScrollView
    ) {
        pagerController = PagerViewController(pages: pages, selectedPageId: selectedPageId)
        self.tabBar = tabBar
        self.headerView = headerView
        self.headerHeight = headerHeight
        self.tabBarHeight = tabBarHeight
        self.scrollViewProvider = scrollViewProvider
        super.init(nibName: nil, bundle: nil)
        tabBar.setSelection(pagerController.selectedPageId)
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
        coordinator = StickyScrollCoordinator(
            chrome: chrome,
            overlay: viewport,
            headerHeight: headerHeight,
            tabBarHeight: tabBarHeight
        )
        pagerController.onPreparePage = { [weak self] id, controller in
            self?.attachPage(id: id, controller: controller)
        }
        pagerController.onRemovePage = { [weak self] id in self?.coordinator?.detach(id) }
        pagerController.onEvent = { [weak self] event in self?.receive(event) }
        tabBar.onSelect = { [weak self] id in self?.pagerController.selectPage(id) }
        // The public pager can create pages before the composite loads its view.
        for (id, controller) in pagerController.preparedPages {
            attachPage(id: id, controller: controller)
        }
        tabBar.setSelection(pagerController.selectedPageId)
        addChild(pagerController)
        viewport.addSubview(pagerController.view)
        pagerController.didMove(toParent: self)
        coordinator?.activate(pagerController.selectedPageId)
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The composite owns safe-area placement; child lists use explicit insets.
        viewport.frame = view.safeAreaLayoutGuide.layoutFrame
        pagerController.view.frame = viewport.bounds
        pagerController.view.setNeedsLayout()
        pagerController.view.layoutIfNeeded()
        headerView.frame = CGRect(
            x: 0,
            y: 0,
            width: pagerController.view.bounds.width,
            height: headerHeight
        )
        tabBar.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: pagerController.view.bounds.width,
            height: tabBarHeight
        )
        coordinator?.layout()
    }

    /// Heights are explicit, finite and nonnegative; update after measuring header content.
    public func setHeaderHeight(_ height: CGFloat, tabBarHeight: CGFloat? = nil) {
        let tabs = tabBarHeight ?? self.tabBarHeight
        headerHeight = height
        self.tabBarHeight = tabs
        coordinator?.updateGeometry(headerHeight: height, tabBarHeight: tabs)
        viewIfLoaded?.setNeedsLayout()
    }

    /// Change business padding through this method while attached. The coordinator
    /// owns its additional top/bottom space; native refresh inset remains separate.
    public func setContentInset(_ inset: UIEdgeInsets, for id: PagerPageId) {
        guard pagerController.pageIds.contains(id) else { return }
        baseInsets[id] = inset
        coordinator?.setBaseInset(inset, for: id)
    }

    /// Replace pages while keeping the existing navigation contents and order.
    @discardableResult
    public func setPages(_ pages: [PagerPage], selectedPageId: PagerPageId? = nil) -> Bool {
        setPages(
            pages,
            navigationPageIds: tabBar.pageIds,
            selectedPageId: selectedPageId,
            updateNavigation: { _ in }
        )
    }

    /// Replace pages and navigation contents before publishing selection events.
    /// Validation and transition checks run before updateNavigation is called.
    /// The closure must synchronously install the supplied navigationPageIds, in
    /// order, without emitting selection intent. Configure display data here;
    /// the container applies the committed selection immediately afterwards.
    @discardableResult
    public func setPages(
        _ pages: [PagerPage],
        navigationPageIds: [PagerPageId],
        selectedPageId: PagerPageId? = nil,
        updateNavigation: (Navigation) -> Void
    ) -> Bool {
        guard pages.map(\.id) == navigationPageIds else {
            return PagerDiagnostics.reject("Navigation identities must match the page order.")
        }
        return pagerController.setPages(
            pages,
            selectedPageId: selectedPageId
        ) {
            updateNavigation(tabBar)
            tabBar.setSelection(pagerController.selectedPageId)
            baseInsets = baseInsets.filter { pagerController.pageIds.contains($0.key) }
            coordinator?.activate(pagerController.selectedPageId)
            viewIfLoaded?.setNeedsLayout()
        }
    }

    override public var childForStatusBarStyle: UIViewController? {
        pagerController
    }

    override public var childForStatusBarHidden: UIViewController? {
        pagerController
    }

    private func attachPage(id: PagerPageId, controller: UIViewController) {
        let scrollView = scrollViewProvider(id, controller)
        coordinator?.attach(scrollView, id: id)
        if let inset = baseInsets[id] { coordinator?.setBaseInset(inset, for: id) }
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

public extension StickyPagerViewController where Navigation == PagerTabBar {
    convenience init(
        pages: [PagerPage],
        items: [PagerTabBar.Item],
        headerView: UIView,
        headerHeight: CGFloat,
        tabBarHeight: CGFloat = 44,
        selectedPageId: PagerPageId? = nil,
        scrollViewProvider: @escaping (PagerPageId, UIViewController) -> UIScrollView
    ) {
        let tabBar = PagerTabBar()
        tabBar.applyValidatedItems(items, selectedPageId: selectedPageId)
        self.init(
            pages: pages,
            tabBar: tabBar,
            headerView: headerView,
            headerHeight: headerHeight,
            tabBarHeight: tabBarHeight,
            selectedPageId: selectedPageId,
            scrollViewProvider: scrollViewProvider
        )
    }

    /// Replace pages and the default tab bar's items as one validated update.
    @discardableResult
    func setPages(
        _ pages: [PagerPage],
        items: [PagerTabBar.Item],
        selectedPageId: PagerPageId? = nil
    ) -> Bool {
        setPages(
            pages,
            navigationPageIds: items.map(\.id),
            selectedPageId: selectedPageId
        ) { tabBar in
            tabBar.applyValidatedItems(items, selectedPageId: nil)
        }
    }
}
