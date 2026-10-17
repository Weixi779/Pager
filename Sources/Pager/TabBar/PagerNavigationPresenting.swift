//
//  PagerNavigationPresenting.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

import UIKit

/// A page navigation view. The container owns its frame and commits selection;
/// the implementation owns its contents, styling and transition presentation.
@MainActor
public protocol PagerNavigationPresenting: AnyObject where Self: UIView {
    /// Navigation identities in the same order as the container's pages.
    var pageIds: [PagerPageId] { get }
    /// Emits selection intent. Applying selection or progress must not emit intent.
    /// The container installs this callback when it loads its view.
    var onSelect: ((PagerPageId) -> Void)? { get set }

    /// Display committed selection and clear any in-flight transition presentation.
    func setSelection(_ id: PagerPageId?)
    /// Display progress between the visible neighboring pages, independently of
    /// the committed selection while a continuous swipe crosses multiple pages.
    func displayTransition(_ transition: PagerTransition)
}

public extension PagerNavigationPresenting {
    /// Forward Pager events to any navigation implementation, including cancellation.
    func receive(_ event: PagerEvent) {
        switch event {
        case let .willTransition(value), let .didUpdateTransition(value): displayTransition(visibleTransition(for: value))
        case let .didFinishTransition(value, completed): setSelection(completed ? value.destination : value.source)
        case let .didSelect(id): setSelection(id)
        }
    }

    private func visibleTransition(for transition: PagerTransition) -> PagerTransition {
        let ids = pageIds
        guard let source = ids.firstIndex(of: transition.source),
              let destination = ids.firstIndex(of: transition.destination),
              abs(destination - source) > 1 else { return transition }

        // Lifecycle events retain the committed source until settling. Navigation
        // instead interpolates the two pages at the current horizontal position.
        let position = CGFloat(source) + CGFloat(destination - source) * transition.progress
        let movingForward = destination > source
        let visibleSource = movingForward
            ? min(Int(floor(position)), destination - 1)
            : max(Int(ceil(position)), destination + 1)
        let visibleDestination = visibleSource + (movingForward ? 1 : -1)
        return PagerTransition(
            source: ids[visibleSource],
            destination: ids[visibleDestination],
            progress: abs(position - CGFloat(visibleSource))
        )
    }
}
