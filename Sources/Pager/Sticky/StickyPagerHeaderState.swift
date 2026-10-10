//
//  StickyPagerHeaderState.swift
//  Pager
//
//  Created by weixi on 2026/10/10.
//

import UIKit

/// Displayed shared-header geometry. Pull-down beyond the expanded top stays at zero.
public struct StickyPagerHeaderState: Equatable, Sendable {
    public let collapseDistance: CGFloat
    public let collapseRange: CGFloat

    public var progress: CGFloat {
        collapseRange > 0 ? collapseDistance / collapseRange : 0
    }
}
