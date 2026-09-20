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
    func displayTransition(_ transition: PagerTransition)
}

public extension PagerNavigationPresenting {
    /// Forward Pager events to any navigation implementation, including cancellation.
    func receive(_ event: PagerEvent) {
        switch event {
        case let .willTransition(value), let .didUpdateTransition(value): displayTransition(value)
        case let .didFinishTransition(value, completed): setSelection(completed ? value.destination : value.source)
        case let .didSelect(id): setSelection(id)
        }
    }
}
