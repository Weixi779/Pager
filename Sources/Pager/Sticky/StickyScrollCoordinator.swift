//
//  StickyScrollCoordinator.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// Each list keeps its own native vertical scroll physics and delegate.
/// The shared chrome lives in the active list; horizontal transitions temporarily
/// move it to the overlay so it does not move sideways with either page.
@MainActor
final class StickyScrollCoordinator {
    @MainActor
    private final class Attachment {
        // Weak keys and values locate pending cleanup without retaining a list or lease.
        private static let current = NSMapTable<UIScrollView, Attachment>.weakToWeakObjects()
        private weak var chrome: UIView?
        private var isRestored = false
        let scrollView: UIScrollView
        let originalAdjustment: UIScrollView.ContentInsetAdjustmentBehavior
        let originalBounces: Bool
        let originalScrollsToTop: Bool
        var baseInset: UIEdgeInsets
        var expandedTopContribution: CGFloat = 0
        var topContribution: CGFloat = 0
        var headerContribution: CGFloat = 0
        var bottomContribution: CGFloat = 0
        var observations: [NSKeyValueObservation] = []
        var isUpdating = false

        static func acquire(_ scrollView: UIScrollView, owner: StickyScrollCoordinator) -> Attachment {
            if let previous = current.object(forKey: scrollView) {
                previous.restore()
            }
            let attachment = Attachment(scrollView, owner: owner)
            current.setObject(attachment, forKey: scrollView)
            return attachment
        }

        private init(_ scrollView: UIScrollView, owner: StickyScrollCoordinator) {
            chrome = owner.chrome
            self.scrollView = scrollView
            originalAdjustment = scrollView.contentInsetAdjustmentBehavior
            originalBounces = scrollView.alwaysBounceVertical
            originalScrollsToTop = scrollView.scrollsToTop
            baseInset = scrollView.contentInset
        }

        /// The fully expanded origin stays fixed while the actual inset shrinks.
        /// Reading, collapse and cleanup must not use the changing native inset.
        var restingTop: CGFloat {
            baseInset.top + expandedTopContribution
        }

        func restore() {
            guard !isRestored else { return }
            isRestored = true
            if Self.current.object(forKey: scrollView) === self {
                Self.current.removeObject(forKey: scrollView)
            }
            observations.removeAll()
            if chrome?.superview === scrollView { chrome?.removeFromSuperview() }
            var inset = scrollView.contentInset
            inset.top -= topContribution
            inset.bottom -= bottomContribution
            let readingDistance = max(0, scrollView.contentOffset.y + restingTop - headerContribution)
            scrollView.contentInset = inset
            scrollView.contentInsetAdjustmentBehavior = originalAdjustment
            scrollView.alwaysBounceVertical = originalBounces
            scrollView.scrollsToTop = originalScrollsToTop
            scrollView.contentOffset.y = readingDistance - scrollView.adjustedContentInset.top
        }
    }

    var onHeaderStateChange: ((StickyPagerHeaderState) -> Void)?
    var headerState: StickyPagerHeaderState {
        StickyPagerHeaderState(collapseDistance: sharedCollapse, collapseRange: geometry.headerHeight)
    }

    private var lastPublishedHeaderState: StickyPagerHeaderState?
    let chrome: UIView
    private weak var overlay: UIView?
    private var attachments: [PagerPageId: Attachment] = [:]
    private(set) var activeId: PagerPageId?
    private(set) var sharedCollapse: CGFloat = 0
    private var overlayOriginY: CGFloat?
    private var isHorizontalTransition: Bool {
        overlayOriginY != nil
    }

    private(set) var geometry: StickyScrollGeometry

    init(
        chrome: UIView,
        overlay: UIView,
        headerHeight: CGFloat,
        tabBarHeight: CGFloat
    ) {
        self.chrome = chrome
        self.overlay = overlay
        geometry = StickyScrollGeometry(headerHeight: headerHeight, tabBarHeight: tabBarHeight)
    }

    deinit {
        // UIKit cleanup stays on the main actor even if the last owner releases
        // the container outside an actor-isolated call. Explicit detach is immediate.
        let retainedAttachments = Array(attachments.values)
        let retainedChrome = chrome
        DispatchQueue.main.async {
            retainedChrome.removeFromSuperview()
            for attachment in retainedAttachments {
                attachment.restore()
            }
        }
    }

    func attach(_ scrollView: UIScrollView, id: PagerPageId) {
        guard attachments[id] == nil else { return }
        let attachment = Attachment.acquire(scrollView, owner: self)
        attachments[id] = attachment
        let originalDistance = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.scrollsToTop = false
        updateInsets(attachment)
        scrollView.contentOffset.y = -attachment.restingTop + originalDistance
        updateInsets(attachment)
        attachment.observations = [
            scrollView.observe(
                \.contentOffset,
                options: [.new]
            ) { [weak self, weak attachment] _, _ in
                // UIKit mutations and synchronous KVO delivery occur on the main
                // actor. Keep delivery synchronous to avoid a one-frame header lag.
                MainActor.assumeIsolated {
                    guard let self, let attachment, !attachment.isUpdating else { return }
                    self.didScroll(id: id)
                }
            },
            scrollView.observe(
                \.contentSize,
                options: [.new]
            ) { [weak self, weak attachment] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let attachment, !attachment.isUpdating else { return }
                    self.updateInsets(attachment)
                    self.layoutChrome()
                }
            },
        ]
    }

    func activate(_ id: PagerPageId?) {
        activeId = id
        for (key, attachment) in attachments {
            attachment.scrollView.scrollsToTop = key == id
        }
        guard let id, let attachment = attachments[id] else {
            overlayOriginY = nil
            sharedCollapse = 0
            chrome.removeFromSuperview()
            publishHeaderState()
            return
        }
        align(attachment)
        overlayOriginY = nil
        didScroll(id: id)
    }

    func beginTransition(to id: PagerPageId) {
        guard let overlay else { return }
        if let activeId, let current = attachments[activeId] {
            current.scrollView.setContentOffset(current.scrollView.contentOffset, animated: false)
        }
        let frame = chrome.superview?.convert(chrome.frame, to: overlay)
        overlayOriginY = frame?.minY ?? -sharedCollapse
        overlay.addSubview(chrome)
        // The first scroll callback arrives after horizontal movement has begun.
        // Preserve vertical position only; copying x would freeze an initial sideways drift.
        if let target = attachments[id] { align(target) }
        layoutChrome()
    }

    func updateGeometry(headerHeight: CGFloat, tabBarHeight: CGFloat) {
        let old = geometry
        geometry = StickyScrollGeometry(headerHeight: headerHeight, tabBarHeight: tabBarHeight)
        sharedCollapse = min(headerHeight, geometry.adjustedDistance(sharedCollapse, from: old))
        if let origin = overlayOriginY {
            overlayOriginY = -geometry.adjustedDistance(-origin, from: old)
        }
        for attachment in attachments.values {
            let distance = attachment.scrollView.contentOffset.y + attachment.restingTop
            updateInsets(attachment)
            let adjustedDistance = geometry.adjustedDistance(distance, from: old)
            attachment.isUpdating = true
            attachment.scrollView.contentOffset.y = adjustedDistance - attachment.restingTop
            attachment.isUpdating = false
            updateInsets(attachment)
        }
        layoutChrome()
    }

    func layout() {
        for attachment in attachments.values {
            updateInsets(attachment)
        }
        layoutChrome()
    }

    func setBaseInset(_ inset: UIEdgeInsets, for id: PagerPageId) {
        guard let attachment = attachments[id] else { return }
        let old = attachment.baseInset
        var actual = attachment.scrollView.contentInset
        actual.top += inset.top - old.top
        actual.bottom += inset.bottom - old.bottom
        actual.left = inset.left
        actual.right = inset.right
        attachment.baseInset = inset
        attachment.isUpdating = true
        attachment.scrollView.contentInset = actual
        attachment.scrollView.contentOffset.y -= inset.top - old.top
        attachment.isUpdating = false
        updateInsets(attachment)
        layoutChrome()
    }

    func detach(_ id: PagerPageId) {
        guard let attachment = attachments.removeValue(forKey: id) else { return }
        let wasActive = activeId == id
        if wasActive { chrome.removeFromSuperview(); activeId = nil }
        attachment.restore()
        if wasActive {
            overlayOriginY = nil
            sharedCollapse = 0
            publishHeaderState()
        }
    }

    func detachAll() {
        for id in Array(attachments.keys) {
            detach(id)
        }
    }

    private func align(_ attachment: Attachment) {
        // Preserve displayed pull-down, including custom refresh and its finishing
        // animation, without depending on a loading state.
        guard attachment.scrollView.contentOffset.y >= -attachment.restingTop else { return }
        attachment.isUpdating = true
        attachment.scrollView.contentOffset.y = geometry.activationOffset(
            currentOffset: attachment.scrollView.contentOffset.y,
            restingTopInset: attachment.restingTop,
            sharedCollapse: sharedCollapse
        )
        attachment.isUpdating = false
        updateInsets(attachment)
    }

    private func updateInsets(_ attachment: Attachment) {
        guard !attachment.isUpdating else { return }
        attachment.isUpdating = true
        defer { attachment.isUpdating = false }
        let scrollView = attachment.scrollView
        attachment.expandedTopContribution = geometry.topContribution
        let collapse = geometry.collapse(offset: scrollView.contentOffset.y, restingTopInset: attachment.restingTop)
        // Native section headers pin against contentInset. Include only the
        // visible shared header so their pinned edge meets the navigation bar.
        let top = geometry.topContribution - collapse
        let bottom = geometry.bottomContribution(
            contentHeight: scrollView.contentSize.height,
            viewportHeight: scrollView.bounds.height,
            baseInset: attachment.baseInset
        )
        var inset = scrollView.contentInset
        // Apply only our delta, preserving native UIRefreshControl's temporary inset.
        inset.top += top - attachment.topContribution
        inset.bottom += bottom - attachment.bottomContribution
        attachment.topContribution = top
        attachment.headerContribution = geometry.headerHeight
        attachment.bottomContribution = bottom
        if scrollView.contentInset != inset {
            let offset = scrollView.contentOffset
            scrollView.contentInset = inset
            scrollView.contentOffset = offset
        }
    }

    private func didScroll(id: PagerPageId) {
        guard let attachment = attachments[id] else { return }
        updateInsets(attachment)
        guard id == activeId, !isHorizontalTransition else { return }
        sharedCollapse = geometry.collapse(offset: attachment.scrollView.contentOffset.y, restingTopInset: attachment.restingTop)
        layoutChrome()
    }

    @discardableResult
    func scrollToTop(of id: PagerPageId, animated: Bool) -> Bool {
        guard !isHorizontalTransition, let attachment = attachments[id] else { return false }
        let scrollView = attachment.scrollView
        // Derive external space before expanding our shrinking inset contribution.
        let externalTop = max(0, scrollView.contentInset.top - attachment.baseInset.top - attachment.topContribution)
        let target = CGPoint(x: scrollView.contentOffset.x, y: -attachment.restingTop - externalTop)
        scrollView.setContentOffset(target, animated: animated)
        return true
    }

    private func publishHeaderState() {
        let state = headerState
        guard state != lastPublishedHeaderState else { return }
        lastPublishedHeaderState = state
        onHeaderStateChange?(state)
    }

    private func layoutChrome() {
        defer { publishHeaderState() }
        if let origin = overlayOriginY {
            guard let overlay else { return }
            chrome.frame = CGRect(
                x: 0,
                y: origin,
                width: overlay.bounds.width,
                height: geometry.topContribution
            )
            return
        }
        guard let activeId, let attachment = attachments[activeId] else { return }
        let scrollView = attachment.scrollView
        if chrome.superview !== scrollView { scrollView.addSubview(chrome) }
        // Clamp chrome between fully expanded and pinned. Further pull-down opens
        // the native refresh area below the bar without moving the shared header.
        // Keeping it inside the list also gives header/bar drags native scroll physics.
        let collapse = geometry.collapse(offset: scrollView.contentOffset.y, restingTopInset: attachment.restingTop)
        chrome.frame = CGRect(
            x: scrollView.contentOffset.x,
            y: scrollView.contentOffset.y - collapse,
            width: scrollView.bounds.width,
            height: geometry.topContribution
        )
        sharedCollapse = collapse
        scrollView.bringSubviewToFront(chrome)
    }
}
