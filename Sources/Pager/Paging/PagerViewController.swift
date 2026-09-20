//
//  PagerViewController.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// A lazy, retaining page container. Offscreen pages remain parented and mounted.
/// Page order is the supplied order; the host decides whether to reverse it for RTL.
@MainActor
public final class PagerViewController: UIViewController {
    public weak var delegate: PagerViewControllerDelegate?
    public private(set) var selectedPageID: PagerPageID?
    public var pageIDs: [PagerPageID] {
        store.pages.map(\.id)
    }

    public var currentViewController: UIViewController? {
        selectedPageID.flatMap { store.controllers[$0] }
    }

    public var isTransitioning: Bool {
        transition != nil
    }

    public var isSwipeEnabled = true {
        didSet { host.scrollView.isScrollEnabled = isSwipeEnabled }
    }

    let host = ScrollPageHost()
    private let store = PageStore()
    private var transition: PagerTransition?
    private var transitionAnimated = false
    private var appearanceIsOpen = false
    private var visibility = Visibility.hidden
    private var isMutating = false
    private var pendingSelection: (id: PagerPageID, animated: Bool, revision: UInt)?
    private var selectionRevision: UInt = 0
    private var lastSize = CGSize.zero
    private var programmaticDestination: Int?
    var onEvent: ((PagerEvent) -> Void)?
    var onPreparePage: ((PagerPageID, UIViewController) -> Void)?
    var onRemovePage: ((PagerPageID) -> Void)?

    private enum Visibility { case hidden, appearing, visible, disappearing }
    private var selectedIndex: Int {
        pageIDs.firstIndex { $0 == selectedPageID } ?? 0
    }

    override public var shouldAutomaticallyForwardAppearanceMethods: Bool {
        false
    }

    override public var childForStatusBarStyle: UIViewController? {
        currentViewController
    }

    override public var childForStatusBarHidden: UIViewController? {
        currentViewController
    }

    public init(pages: [PagerPage], selectedPageID: PagerPageID? = nil) throws {
        try PageStore.validate(pages, selection: selectedPageID)
        self.selectedPageID = selectedPageID ?? pages.first?.id
        super.init(nibName: nil, bundle: nil)
        _ = store.replace(with: pages)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        view = host
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        host.onScroll = { [weak self] in self?.didScroll(to: $0) }
        host.onBeginDragging = { [weak self] in
            guard let self else { return }
            performMutation {
                self.programmaticDestination = nil
                self.finishTransition(completed: false)
            }
        }
        host.onSettle = { [weak self] in self?.settle() }
        if !store.pages.isEmpty { preparePage(at: selectedIndex) }
        configureHost()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard lastSize != view.bounds.size else { return }
        performMutation {
            host.stop()
            programmaticDestination = nil
            finishTransition(completed: false)
            lastSize = view.bounds.size
            configureHost()
        }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visibility = .appearing
        currentViewController?.beginAppearanceTransition(true, animated: animated)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        currentViewController?.endAppearanceTransition()
        visibility = .visible
        drainPendingSelection()
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        performMutation {
            host.stop()
            programmaticDestination = nil
            finishTransition(completed: false)
            host.layoutPages(selectedIndex: selectedIndex)
            visibility = .disappearing
            currentViewController?.beginAppearanceTransition(false, animated: animated)
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        currentViewController?.endAppearanceTransition()
        visibility = .hidden
        drainPendingSelection()
    }

    /// Returns false for an unknown ID. Reentrant selections are coalesced to the
    /// most recent request and applied after the current event or parent appearance.
    @discardableResult
    public func selectPage(_ id: PagerPageID, animated: Bool = true) -> Bool {
        guard pageIDs.contains(id) else { return false }
        selectionRevision &+= 1
        guard !isMutating, visibility != .appearing, visibility != .disappearing else {
            pendingSelection = (id, animated, selectionRevision)
            return true
        }
        loadViewIfNeeded()
        view.layoutIfNeeded()
        performMutation {
            host.stop()
            programmaticDestination = nil
            finishTransition(completed: false)
            host.layoutPages(selectedIndex: selectedIndex)
            guard id != selectedPageID, let index = pageIDs.firstIndex(of: id) else { return }
            // Nonadjacent jumps do not instantiate intermediate pages.
            let shouldAnimate = animated && visibility == .visible && host.pageWidth > 0 && abs(index - selectedIndex) == 1
            beginTransition(to: index, animated: shouldAnimate)
            programmaticDestination = index
            host.move(to: index, animated: shouldAnimate)
            if !shouldAnimate {
                programmaticDestination = nil
                finishTransition(completed: true)
            }
        }
        return true
    }

    /// Atomic validation; retained IDs keep their controller and reading state.
    /// Call after a transition/parent appearance finishes, not from an event callback.
    public func setPages(_ pages: [PagerPage], selectedPageID: PagerPageID? = nil) throws {
        try PageStore.validate(pages, selection: selectedPageID)
        guard !isMutating, !isTransitioning, !host.scrollView.isDragging,
              !host.scrollView.isDecelerating, visibility != .appearing, visibility != .disappearing else {
            throw PagerError.transitionInProgress
        }
        selectionRevision &+= 1
        pendingSelection = nil
        performMutation {
            let oldID = self.selectedPageID
            let newID = selectedPageID ?? pages.first(where: { $0.id == oldID })?.id ?? pages.first?.id
            let oldController = currentViewController
            if oldID != newID, visibility == .visible {
                oldController?.beginAppearanceTransition(false, animated: false)
            }
            let removed = store.replace(with: pages)
            self.selectedPageID = newID
            if isViewLoaded, let newID, let index = pageIDs.firstIndex(of: newID) {
                preparePage(at: index)
                if oldID != newID, visibility == .visible {
                    currentViewController?.beginAppearanceTransition(true, animated: false)
                }
            }
            if oldID != newID, visibility == .visible {
                oldController?.endAppearanceTransition()
                currentViewController?.endAppearanceTransition()
            }
            for (id, controller) in removed {
                onRemovePage?(id)
                controller.willMove(toParent: nil)
                controller.viewIfLoaded?.removeFromSuperview()
                controller.removeFromParent()
            }
            if isViewLoaded { configureHost() }
            if oldID != newID { emit(.didSelect(newID)) }
        }
    }

    private func preparePage(at index: Int) {
        guard store.pages.indices.contains(index) else { return }
        let (controller, created) = store.controller(at: index)
        if created {
            addChild(controller)
            controller.view.accessibilityElementsHidden = pageIDs[index] != selectedPageID
            host.mount(controller.view, at: index)
            controller.didMove(toParent: self)
            onPreparePage?(pageIDs[index], controller)
        } else {
            host.mount(controller.view, at: index)
        }
    }

    private func configureHost() {
        var views: [Int: UIView] = [:]
        for (index, id) in pageIDs.enumerated() {
            if let controller = store.controllers[id] { views[index] = controller.view }
        }
        host.configure(pageCount: pageIDs.count, views: views, selectedIndex: selectedIndex)
        updateAccessibility()
    }

    private func beginTransition(to index: Int, animated: Bool) {
        guard let source = selectedPageID, pageIDs.indices.contains(index), pageIDs[index] != source else { return }
        preparePage(at: index)
        transitionAnimated = animated
        let value = PagerTransition(source: source, destination: pageIDs[index], progress: 0)
        transition = value
        if visibility == .visible {
            store.controllers[source]?.beginAppearanceTransition(false, animated: animated)
            store.controllers[value.destination]?.beginAppearanceTransition(true, animated: animated)
            appearanceIsOpen = true
        }
        emit(.willTransition(value))
    }

    private func didScroll(to position: CGFloat) {
        guard !isMutating, pageIDs.count > 1, position.isFinite else { return }
        performMutation {
            let origin = selectedIndex
            let bounded = min(max(position, 0), CGFloat(pageIDs.count - 1))
            let index = programmaticDestination ?? (bounded > CGFloat(origin) ? Int(ceil(bounded)) : Int(floor(bounded)))
            if index == origin {
                finishTransition(completed: false)
                return
            }
            if transition?.destination != pageIDs[index] {
                finishTransition(completed: false)
                beginTransition(to: index, animated: true)
            }
            // The two visible pages may differ from the committed source after a fast fling.
            preparePage(at: Int(floor(bounded)))
            preparePage(at: Int(ceil(bounded)))
            if let transition {
                let progress = min(max(abs(bounded - CGFloat(origin)) / CGFloat(abs(index - origin)), 0), 1)
                let value = PagerTransition(source: transition.source, destination: transition.destination, progress: progress)
                self.transition = value
                emit(.didUpdateTransition(value))
            }
        }
    }

    private func settle() {
        guard !isMutating, !pageIDs.isEmpty else { return }
        performMutation {
            let index = min(max(Int(host.position.rounded()), 0), pageIDs.count - 1)
            programmaticDestination = nil
            if index == selectedIndex {
                finishTransition(completed: false)
            } else {
                if transition?.destination != pageIDs[index] {
                    finishTransition(completed: false)
                    beginTransition(to: index, animated: true)
                }
                finishTransition(completed: true)
            }
            host.layoutPages(selectedIndex: selectedIndex)
        }
    }

    private func finishTransition(completed: Bool) {
        guard let transition else { return }
        let source = store.controllers[transition.source]
        let destination = store.controllers[transition.destination]
        if appearanceIsOpen {
            if !completed {
                // UIKit supports reversing an unfinished appearance transition.
                source?.beginAppearanceTransition(true, animated: transitionAnimated)
                destination?.beginAppearanceTransition(false, animated: transitionAnimated)
            }
            source?.endAppearanceTransition()
            destination?.endAppearanceTransition()
            appearanceIsOpen = false
        }
        self.transition = nil
        if completed { selectedPageID = transition.destination }
        updateAccessibility()
        let final = PagerTransition(source: transition.source, destination: transition.destination, progress: completed ? 1 : 0)
        emit(.didFinishTransition(final, completed: completed))
        if completed {
            setNeedsStatusBarAppearanceUpdate()
            emit(.didSelect(selectedPageID))
        }
    }

    private func updateAccessibility() {
        for (id, controller) in store.controllers {
            controller.viewIfLoaded?.accessibilityElementsHidden = id != selectedPageID
        }
    }

    private func emit(_ event: PagerEvent) {
        onEvent?(event)
        delegate?.pager(self, didReceive: event)
    }

    private func performMutation(_ body: () -> Void) {
        guard !isMutating else { return }
        isMutating = true
        body()
        isMutating = false
        drainPendingSelection()
    }

    private func drainPendingSelection() {
        guard let request = pendingSelection, !isMutating,
              visibility != .appearing, visibility != .disappearing else { return }
        pendingSelection = nil
        // Break recursive delegate-driven selection chains.
        DispatchQueue.main.async { [weak self] in
            guard let self, selectionRevision == request.revision else { return }
            selectPage(request.id, animated: request.animated)
        }
    }
}
