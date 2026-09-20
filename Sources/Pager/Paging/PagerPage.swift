//
//  PagerPage.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// Stable identity, independent of a page's position in the current array.
public struct PagerPageId: Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }
}

/// The factory runs on first display. A retained Id keeps its existing controller
/// when descriptors are replaced; use a new Id to replace the controller itself.
@MainActor
public struct PagerPage {
    public let id: PagerPageId
    let makeViewController: @MainActor () -> UIViewController

    public init(id: PagerPageId, makeViewController: @escaping @MainActor () -> UIViewController) {
        self.id = id
        self.makeViewController = makeViewController
    }
}

public struct PagerTransition: Equatable {
    public let source: PagerPageId
    public let destination: PagerPageId
    public let progress: CGFloat

    public init(source: PagerPageId, destination: PagerPageId, progress: CGFloat) {
        self.source = source
        self.destination = destination
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
    }
}

public enum PagerEvent {
    case willTransition(PagerTransition)
    case didUpdateTransition(PagerTransition)
    case didFinishTransition(PagerTransition, completed: Bool)
    case didSelect(PagerPageId?)
}

@MainActor
public protocol PagerViewControllerDelegate: AnyObject {
    func pager(_ pager: any PagerControlling, didReceive event: PagerEvent)
}
