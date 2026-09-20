//
//  PagerControlling.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

import UIKit

/// Query and control pagination without replacing its page collection.
@MainActor
public protocol PagerControlling: AnyObject {
    var pageIds: [PagerPageId] { get }
    var selectedPageId: PagerPageId? { get }
    var currentViewController: UIViewController? { get }
    var isTransitioning: Bool { get }
    var isSwipeEnabled: Bool { get set }
    var delegate: (any PagerViewControllerDelegate)? { get set }

    /// True means the request was accepted, not that a transition completed.
    @discardableResult
    func selectPage(_ id: PagerPageId, animated: Bool) -> Bool
}

public extension PagerControlling {
    @discardableResult
    func selectPage(_ id: PagerPageId) -> Bool {
        selectPage(id, animated: true)
    }
}
