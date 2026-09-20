//
//  StickyScrollGeometry.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

struct StickyScrollGeometry {
    var headerHeight: CGFloat
    var tabBarHeight: CGFloat

    var topContribution: CGFloat {
        headerHeight + tabBarHeight
    }

    func bottomContribution(contentHeight: CGFloat, viewportHeight: CGFloat, baseInset: UIEdgeInsets) -> CGFloat {
        max(0, viewportHeight - tabBarHeight - contentHeight - baseInset.top - baseInset.bottom)
    }

    func collapse(offset: CGFloat, restingTopInset: CGFloat) -> CGFloat {
        min(max(offset + restingTopInset, 0), headerHeight)
    }

    /// Expanded shared chrome takes precedence. Once pinned, preserve deep reading.
    func activationOffset(currentOffset: CGFloat, restingTopInset: CGFloat, sharedCollapse: CGFloat) -> CGFloat {
        let distance = sharedCollapse < headerHeight ? sharedCollapse : max(headerHeight, currentOffset + restingTopInset)
        return distance - restingTopInset
    }
}
