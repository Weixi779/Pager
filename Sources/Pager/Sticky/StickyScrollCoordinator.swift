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
        let scrollView: UIScrollView
        let originalAdjustment: UIScrollView.ContentInsetAdjustmentBehavior
        let originalBounces: Bool
        let originalScrollsToTop: Bool
        var baseInset: UIEdgeInsets
        var topContribution: CGFloat = 0
        var headerContribution: CGFloat = 0
        var bottomContribution: CGFloat = 0
        var observations: [NSKeyValueObservation] = []
        var isUpdating = false

        init(_ scrollView: UIScrollView) {
            self.scrollView = scrollView
            originalAdjustment = scrollView.contentInsetAdjustmentBehavior
            originalBounces = scrollView.alwaysBounceVertical
            originalScrollsToTop = scrollView.scrollsToTop
            baseInset = scrollView.contentInset
        }

        var restingTop: CGFloat {
            baseInset.top + topContribution
        }

        func restore() {
            observations.removeAll()
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

    let chrome: UIView
    private weak var overlay: UIView?
    private var attachments: [PagerPageID: Attachment] = [:]
    private(set) var activeID: PagerPageID?
    private(set) var sharedCollapse: CGFloat = 0
    private var isHorizontalTransition = false
    private(set) var geometry: StickyScrollGeometry

    init(chrome: UIView, overlay: UIView, headerHeight: CGFloat, tabBarHeight: CGFloat) {
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

    func attach(_ scrollView: UIScrollView, id: PagerPageID) {
        guard attachments[id] == nil else { return }
        precondition(!attachments.values.contains { $0.scrollView === scrollView }, "Each page needs its own scroll view.")
        let attachment = Attachment(scrollView)
        attachments[id] = attachment
        let originalDistance = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.alwaysBounceVertical = true
        scrollView.scrollsToTop = false
        updateInsets(attachment)
        scrollView.contentOffset.y = -attachment.restingTop + originalDistance
        attachment.observations = [
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self, weak attachment] _, _ in
                // UIKit mutations and synchronous KVO delivery occur on the main
                // actor. Keep delivery synchronous to avoid a one-frame header lag.
                MainActor.assumeIsolated {
                    guard let self, let attachment, !attachment.isUpdating else { return }
                    self.didScroll(id: id)
                }
            },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self, weak attachment] _, _ in
                MainActor.assumeIsolated {
                    guard let self, let attachment, !attachment.isUpdating else { return }
                    self.updateInsets(attachment)
                    self.layoutChrome()
                }
            },
        ]
    }

    func activate(_ id: PagerPageID?) {
        activeID = id
        for (key, attachment) in attachments {
            attachment.scrollView.scrollsToTop = key == id
        }
        guard let id, let attachment = attachments[id] else {
            chrome.removeFromSuperview()
            return
        }
        align(attachment)
        isHorizontalTransition = false
        didScroll(id: id)
    }

    func beginTransition(to id: PagerPageID) {
        guard let overlay else { return }
        if let activeID, let current = attachments[activeID] {
            current.scrollView.setContentOffset(current.scrollView.contentOffset, animated: false)
        }
        let frame = chrome.superview?.convert(chrome.frame, to: overlay)
        isHorizontalTransition = true
        overlay.addSubview(chrome)
        // The first scroll callback arrives after horizontal movement has begun.
        // Preserve vertical position only; copying x would freeze an initial sideways drift.
        chrome.frame = CGRect(x: 0, y: frame?.minY ?? -sharedCollapse,
                              width: overlay.bounds.width, height: geometry.topContribution)
        if let target = attachments[id] { align(target) }
    }

    func updateGeometry(headerHeight: CGFloat, tabBarHeight: CGFloat) {
        let old = geometry
        geometry = StickyScrollGeometry(headerHeight: headerHeight, tabBarHeight: tabBarHeight)
        sharedCollapse = old.headerHeight > 0 ? min(headerHeight, sharedCollapse / old.headerHeight * headerHeight) : 0
        for attachment in attachments.values {
            let distance = attachment.scrollView.contentOffset.y + attachment.restingTop
            updateInsets(attachment)
            let adjustedDistance: CGFloat =
                if distance >= old.headerHeight {
                    headerHeight + distance - old.headerHeight
                } else if distance < 0 {
                    distance
                } else {
                    old.headerHeight > 0 ? distance / old.headerHeight * headerHeight : 0
                }
            attachment.isUpdating = true
            attachment.scrollView.contentOffset.y = adjustedDistance - attachment.restingTop
            attachment.isUpdating = false
        }
        layoutChrome()
    }

    func layout() {
        for attachment in attachments.values {
            updateInsets(attachment)
        }
        layoutChrome()
    }

    func setBaseInset(_ inset: UIEdgeInsets, for id: PagerPageID) {
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

    func detach(_ id: PagerPageID) {
        guard let attachment = attachments.removeValue(forKey: id) else { return }
        if activeID == id { chrome.removeFromSuperview(); activeID = nil }
        attachment.restore()
    }

    func detachAll() {
        for id in Array(attachments.keys) {
            detach(id)
        }
    }

    private func align(_ attachment: Attachment) {
        // Do not disturb a refresh already in progress when returning to its tab.
        guard attachment.scrollView.refreshControl?.isRefreshing != true else { return }
        attachment.isUpdating = true
        attachment.scrollView.contentOffset.y = geometry.activationOffset(
            currentOffset: attachment.scrollView.contentOffset.y,
            restingTopInset: attachment.restingTop, sharedCollapse: sharedCollapse
        )
        attachment.isUpdating = false
    }

    private func updateInsets(_ attachment: Attachment) {
        guard !attachment.isUpdating else { return }
        attachment.isUpdating = true
        defer { attachment.isUpdating = false }
        let scrollView = attachment.scrollView
        let top = geometry.topContribution
        let bottom = geometry.bottomContribution(contentHeight: scrollView.contentSize.height,
                                                 viewportHeight: scrollView.bounds.height, baseInset: attachment.baseInset)
        var inset = scrollView.contentInset
        // Apply only our delta, preserving native UIRefreshControl's temporary inset.
        inset.top += top - attachment.topContribution
        inset.bottom += bottom - attachment.bottomContribution
        attachment.topContribution = top
        attachment.headerContribution = geometry.headerHeight
        attachment.bottomContribution = bottom
        if scrollView.contentInset != inset { scrollView.contentInset = inset }
    }

    private func didScroll(id: PagerPageID) {
        guard id == activeID, !isHorizontalTransition, let attachment = attachments[id] else { return }
        sharedCollapse = geometry.collapse(offset: attachment.scrollView.contentOffset.y, restingTopInset: attachment.restingTop)
        layoutChrome()
    }

    private func layoutChrome() {
        guard !isHorizontalTransition, let activeID, let attachment = attachments[activeID] else { return }
        let scrollView = attachment.scrollView
        if chrome.superview !== scrollView { scrollView.addSubview(chrome) }
        // Once collapsed, pin the tab bar by moving chrome in content coordinates.
        // Keeping it inside the list also gives header/bar drags native scroll physics.
        chrome.frame = CGRect(x: scrollView.contentOffset.x,
                              y: max(-attachment.restingTop, scrollView.contentOffset.y - geometry.headerHeight),
                              width: scrollView.bounds.width, height: geometry.topContribution)
        scrollView.bringSubviewToFront(chrome)
    }
}
