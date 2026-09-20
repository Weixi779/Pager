//
//  PagerPage.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// Stable identity, independent of a page's position in the current array.
public struct PagerPageID: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

/// The factory runs on first display. A retained ID keeps its existing controller
/// when descriptors are replaced; use a new ID to replace the controller itself.
@MainActor
public struct PagerPage {
    public let id: PagerPageID
    let makeViewController: @MainActor () -> UIViewController

    public init(id: PagerPageID, makeViewController: @escaping @MainActor () -> UIViewController) {
        self.id = id
        self.makeViewController = makeViewController
    }
}

public enum PagerError: Error, Equatable {
    case duplicatePageID(PagerPageID)
    case unknownPageID(PagerPageID)
    case transitionInProgress
    case tabItemsDoNotMatchPages
}

public struct PagerTransition: Equatable {
    public let source: PagerPageID
    public let destination: PagerPageID
    public let progress: CGFloat

    public init(source: PagerPageID, destination: PagerPageID, progress: CGFloat) {
        self.source = source
        self.destination = destination
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
    }
}

public enum PagerEvent {
    case willTransition(PagerTransition)
    case didUpdateTransition(PagerTransition)
    case didFinishTransition(PagerTransition, completed: Bool)
    case didSelect(PagerPageID?)
}

@MainActor
public protocol PagerViewControllerDelegate: AnyObject {
    func pager(_ pager: PagerViewController, didReceive event: PagerEvent)
}
