//
//  PagerTabBarTests.swift
//  PagerTests
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

@testable import Pager
import Testing
import UIKit

@MainActor
@Suite("Pager tab bar")
struct PagerTabBarTests {
    @Test("Taps emit intent without prematurely committing selection")
    func intent() throws {
        let bar = PagerTabBar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        try bar.setItems([.init(id: "a", title: "精选"), .init(id: "b", title: "发现")], selectedPageID: "a")
        var intent: PagerPageID?
        bar.onSelect = { intent = $0 }
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        let buttons = scroll.subviews.compactMap { $0 as? UIButton }
        // SwiftPM's headless test runner has no UIApplication event dispatch.
        // Verify the registered action and invoke it; the demo UI tests exercise taps.
        let action = try #require(buttons[1].actions(forTarget: bar, forControlEvent: .touchUpInside)?.first)
        bar.perform(NSSelectorFromString(action), with: buttons[1])
        #expect(intent == "b")
        #expect(bar.selectedPageID == "a")
        bar.setSelection("b")
        #expect(buttons[1].accessibilityTraits.contains(.selected))
        #expect(!buttons[0].accessibilityTraits.contains(.selected))
    }

    @Test("Equal distribution uses the same width even when one title exceeds its share")
    func equalWidths() throws {
        let bar = PagerTabBar(frame: CGRect(x: 0, y: 0, width: 160, height: 44))
        var configuration = PagerTabBar.Configuration()
        configuration.distributesItemsEqually = true
        bar.configuration = configuration
        try bar.setItems([.init(id: "a", title: "A"), .init(id: "b", title: "A much longer title")])
        bar.layoutIfNeeded()
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        let buttons = scroll.subviews.compactMap { $0 as? UIButton }
        #expect(buttons[0].bounds.width == buttons[1].bounds.width)
        #expect(scroll.contentSize.width > bar.bounds.width)
    }

    @Test("Indicator interpolates and a cancelled transition restores source selection")
    func transition() throws {
        let bar = PagerTabBar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        try bar.setItems([.init(id: "a", title: "A"), .init(id: "b", title: "Long title")], selectedPageID: "a")
        bar.layoutIfNeeded()
        let scroll = try #require(bar.subviews.first as? UIScrollView)
        let indicator = try #require(scroll.subviews.first { !($0 is UIButton) && $0.layer.cornerRadius > 0 })
        let start = indicator.frame
        let transition = PagerTransition(source: "a", destination: "b", progress: 0.5)
        bar.displayTransition(transition)
        let middle = indicator.frame
        bar.setSelection("b")
        let end = indicator.frame
        #expect(abs(middle.midX - (start.midX + end.midX) / 2) < 0.01)
        #expect(abs(middle.width - (start.width + end.width) / 2) < 0.01)
        bar.receive(.didFinishTransition(transition, completed: false))
        #expect(bar.selectedPageID == "a")
        #expect(indicator.frame == start)
    }
}
