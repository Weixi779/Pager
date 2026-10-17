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
public final class PagerViewController: UIViewController, PagerControlling {
    public weak var delegate: (any PagerViewControllerDelegate)?
    public private(set) var selectedPageId: PagerPageId?
    public var pageIds: [PagerPageId] {
        store.pages.map(\.id)
    }

    public var currentViewController: UIViewController? {
        selectedPageId.flatMap { store.controllers[$0] }
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
    private var isForwardingAppearance = false
    private var pendingParentAppearances: [ParentAppearance] = []
    private var visibility = Visibility.hidden
    private var isMutating = false
    private var pendingSelection: (id: PagerPageId, animated: Bool, revision: UInt)?
    private var selectionRevision: UInt = 0
    private var lastSize = CGSize.zero
    private var programmaticDestination: Int?
    var onEvent: ((PagerEvent) -> Void)?
    var onPreparePage: ((PagerPageId, UIViewController) -> Void)?
    var onRemovePage: ((PagerPageId) -> Void)?

    /// Already-created pages, in descriptor order; reading this never runs factories.
    var preparedPages: [(id: PagerPageId, controller: UIViewController)] {
        store.pages.compactMap { page in
            store.controllers[page.id].map { (page.id, $0) }
        }
    }

    private enum Visibility { case hidden, appearing, visible, disappearing }
    private enum ParentAppearance {
        case willAppear(Bool), didAppear, willDisappear(Bool), didDisappear
    }

    private var selectedIndex: Int {
        pageIds.firstIndex { $0 == selectedPageId } ?? 0
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

    /// Initial identities must be unique and contain the requested selection.
    /// Initial configuration is a caller contract; runtime replacements are validated.
    public init(pages: [PagerPage] = [], selectedPageId: PagerPageId? = nil) {
        self.selectedPageId = selectedPageId ?? pages.first?.id
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
                // A new drag takes over at the current offset, including during
                // deceleration. Keep its appearance and navigation progress open.
                self.programmaticDestination = nil
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
        receiveParentAppearance(.willAppear(animated))
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        receiveParentAppearance(.didAppear)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        receiveParentAppearance(.willDisappear(animated))
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        receiveParentAppearance(.didDisappear)
    }

    private func receiveParentAppearance(_ appearance: ParentAppearance) {
        pendingParentAppearances.append(appearance)
        drainParentAppearances()
    }

    private func drainParentAppearances() {
        guard !isForwardingAppearance else { return }
        withMutationScope {
            while !pendingParentAppearances.isEmpty {
                let appearance = pendingParentAppearances.removeFirst()
                isForwardingAppearance = true
                switch appearance {
                case let .willAppear(animated):
                    visibility = .appearing
                    currentViewController?.beginAppearanceTransition(true, animated: animated)
                case .didAppear:
                    currentViewController?.endAppearanceTransition()
                    visibility = .visible
                case let .willDisappear(animated):
                    visibility = .disappearing
                    host.stop()
                    programmaticDestination = nil
                    finishTransition(completed: false)
                    host.layoutPages(selectedIndex: selectedIndex)
                    currentViewController?.beginAppearanceTransition(false, animated: animated)
                case .didDisappear:
                    currentViewController?.endAppearanceTransition()
                    visibility = .hidden
                }
                isForwardingAppearance = false
            }
        }
    }

    /// Finish the current group of child callbacks before forwarding a parent
    /// lifecycle change. UIKit may synchronously reenter from any child callback.
    private func withAppearanceForwarding(_ body: () -> Void) {
        let wasForwarding = isForwardingAppearance
        isForwardingAppearance = true
        body()
        isForwardingAppearance = wasForwarding
        if !wasForwarding { drainParentAppearances() }
    }

    /// True means accepted, not completed. Returns false for an unknown Id.
    /// Reentrant selections are coalesced to the most recent request and applied
    /// after the current event or parent appearance.
    @discardableResult
    public func selectPage(_ id: PagerPageId, animated: Bool = true) -> Bool {
        guard pageIds.contains(id) else {
            return PagerDiagnostics.reject("Cannot select a page that is not in the container.")
        }
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
            guard id != selectedPageId, let index = pageIds.firstIndex(of: id) else { return }
            // Nonadjacent jumps do not instantiate intermediate pages.
            let shouldAnimate = animated && visibility == .visible && host.pageWidth > 0 && abs(index - selectedIndex) == 1
            beginTransition(to: index, animated: shouldAnimate)
            // A synchronous lifecycle callback may have cancelled this transition.
            guard transition?.destination == id else { return }
            programmaticDestination = index
            host.move(to: index, animated: shouldAnimate)
            if !shouldAnimate {
                programmaticDestination = nil
                finishTransition(completed: true)
            }
        }
        return true
    }

    /// Atomic validation; retained Ids keep their controller and reading state.
    /// Call after a transition/parent appearance finishes, not from an event callback.
    @discardableResult
    public func setPages(_ pages: [PagerPage], selectedPageId: PagerPageId? = nil) -> Bool {
        setPages(
            pages,
            selectedPageId: selectedPageId,
            synchronize: {}
        )
    }

    /// Commit composite state before publishing events, inside the same mutation
    /// boundary so callback-driven replacements and selections keep their rules.
    @discardableResult
    func setPages(
        _ pages: [PagerPage],
        selectedPageId: PagerPageId?,
        synchronize: () -> Void
    ) -> Bool {
        guard PageStore.validate(pages, selection: selectedPageId) else { return false }
        guard !isMutating, !isTransitioning, !host.scrollView.isDragging,
              !host.scrollView.isDecelerating, visibility != .appearing, visibility != .disappearing else {
            return PagerDiagnostics.reject("Cannot replace pages during a transition, appearance callback or another update.")
        }
        selectionRevision &+= 1
        pendingSelection = nil
        performMutation {
            withAppearanceForwarding {
                let oldId = self.selectedPageId
                let newId = selectedPageId ?? pages.first(where: { $0.id == oldId })?.id ?? pages.first?.id
                let oldController = currentViewController
                if oldId != newId, visibility == .visible {
                    oldController?.beginAppearanceTransition(false, animated: false)
                }
                let removed = store.replace(with: pages)
                self.selectedPageId = newId
                if isViewLoaded, let newId, let index = pageIds.firstIndex(of: newId) {
                    preparePage(at: index)
                    if oldId != newId, visibility == .visible {
                        currentViewController?.beginAppearanceTransition(true, animated: false)
                    }
                }
                if oldId != newId, visibility == .visible {
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
                synchronize()
                if oldId != newId {
                    setNeedsStatusBarAppearanceUpdate()
                    emit(.didSelect(newId))
                }
            }
        }
        return true
    }

    private func preparePage(at index: Int) {
        guard store.pages.indices.contains(index) else { return }
        let (controller, created) = store.controller(at: index)
        if created {
            addChild(controller)
            controller.view.accessibilityElementsHidden = pageIds[index] != selectedPageId
            host.mount(controller.view, at: index)
            controller.didMove(toParent: self)
            onPreparePage?(pageIds[index], controller)
        } else {
            host.mount(controller.view, at: index)
        }
    }

    private func configureHost() {
        var views: [Int: UIView] = [:]
        for (index, id) in pageIds.enumerated() {
            if let controller = store.controllers[id] { views[index] = controller.view }
        }
        host.configure(
            pageCount: pageIds.count,
            views: views,
            selectedIndex: selectedIndex
        )
        updateAccessibility()
    }

    private func beginTransition(to index: Int, animated: Bool) {
        guard let source = selectedPageId, pageIds.indices.contains(index), pageIds[index] != source else { return }
        preparePage(at: index)
        transitionAnimated = animated
        let value = PagerTransition(
            source: source,
            destination: pageIds[index],
            progress: 0
        )
        transition = value
        withAppearanceForwarding {
            if visibility == .visible {
                appearanceIsOpen = true
                store.controllers[source]?.beginAppearanceTransition(false, animated: animated)
                store.controllers[value.destination]?.beginAppearanceTransition(true, animated: animated)
            }
            emit(.willTransition(value))
        }
    }

    private func didScroll(to position: CGFloat) {
        guard !isMutating, pageIds.count > 1, position.isFinite else { return }
        performMutation {
            let origin = selectedIndex
            let bounded = min(max(position, 0), CGFloat(pageIds.count - 1))
            let index = programmaticDestination ?? (bounded > CGFloat(origin) ? Int(ceil(bounded)) : Int(floor(bounded)))
            if index == origin {
                finishTransition(completed: false)
                return
            }
            if transition?.destination != pageIds[index] {
                finishTransition(completed: false)
                beginTransition(to: index, animated: true)
            }
            // The two visible pages may differ from the committed source after a fast fling.
            preparePage(at: Int(floor(bounded)))
            preparePage(at: Int(ceil(bounded)))
            if let transition {
                let progress = min(max(abs(bounded - CGFloat(origin)) / CGFloat(abs(index - origin)), 0), 1)
                let value = PagerTransition(
                    source: transition.source,
                    destination: transition.destination,
                    progress: progress
                )
                self.transition = value
                emit(.didUpdateTransition(value))
            }
        }
    }

    private func settle() {
        guard !isMutating, !pageIds.isEmpty else { return }
        performMutation {
            let index = min(max(Int(host.position.rounded()), 0), pageIds.count - 1)
            programmaticDestination = nil
            if index == selectedIndex {
                finishTransition(completed: false)
            } else {
                if transition?.destination != pageIds[index] {
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
        let shouldFinishAppearance = appearanceIsOpen
        appearanceIsOpen = false
        self.transition = nil
        if completed { selectedPageId = transition.destination }
        withAppearanceForwarding {
            if shouldFinishAppearance {
                if !completed {
                    // UIKit supports reversing an unfinished appearance transition.
                    source?.beginAppearanceTransition(true, animated: transitionAnimated)
                    destination?.beginAppearanceTransition(false, animated: transitionAnimated)
                }
                source?.endAppearanceTransition()
            }
            let final = PagerTransition(
                source: transition.source,
                destination: transition.destination,
                progress: completed ? 1 : 0
            )
            if completed { delegate?.pager(self, didCommit: final) }
            if shouldFinishAppearance { destination?.endAppearanceTransition() }
            updateAccessibility()
            emit(.didFinishTransition(final, completed: completed))
            if completed {
                setNeedsStatusBarAppearanceUpdate()
                emit(.didSelect(selectedPageId))
            }
        }
    }

    private func updateAccessibility() {
        for (id, controller) in store.controllers {
            controller.viewIfLoaded?.accessibilityElementsHidden = id != selectedPageId
        }
    }

    private func emit(_ event: PagerEvent) {
        onEvent?(event)
        delegate?.pager(self, didReceive: event)
    }

    private func performMutation(_ body: () -> Void) {
        guard !isMutating else { return }
        withMutationScope(body)
    }

    private func withMutationScope(_ body: () -> Void) {
        let wasMutating = isMutating
        isMutating = true
        defer {
            isMutating = wasMutating
            if !wasMutating { drainPendingSelection() }
        }
        body()
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
