//
//  PagerDemoUITests.swift
//  PagerDemo
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import XCTest

final class PagerDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHeaderSwipePinsTabsAndSwitchesRetainedPages() {
        let app = XCUIApplication()
        app.launch()
        let header = app.staticTexts["sharedHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let selected = app.buttons["精选"]
        let initialY = selected.frame.minY
        // Start in the common header: the active list must receive this gesture.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.25)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.07))
        )
        let pinned = NSPredicate { _, _ in selected.frame.minY < initialY - 100 }
        expectation(for: pinned, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        app.tables["list-long"].swipeUp()
        let position = app.tables["list-long"].cells.firstMatch.label
        app.buttons["发现"].tap()
        XCTAssertTrue(app.tables["list-short"].waitForExistence(timeout: 3))
        app.buttons["精选"].tap()
        XCTAssertTrue(app.tables["list-long"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.tables["list-long"].cells.firstMatch.label, position)
        attachScreenshot("pinned-return")
    }

    @MainActor
    func testRefreshRequiresExpandedHeaderAndOnlyRefreshesCurrentTab() {
        let app = XCUIApplication()
        app.launchArguments = ["--start-pinned"]
        app.launch()
        let table = app.tables["list-long"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        table.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.45)).press(
            forDuration: 0.05,
            thenDragTo: table.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.52))
        )
        XCTAssertEqual(table.value as? String, "refreshes:0", "Partial header expansion must not refresh")
        pullToRefresh(table)
        let refreshed = NSPredicate(format: "value == %@", "refreshes:1")
        expectation(for: refreshed, evaluatedWith: table)
        waitForExpectations(timeout: 5)
        app.buttons["发现"].tap()
        let short = app.tables["list-short"]
        XCTAssertTrue(short.waitForExistence(timeout: 3))
        XCTAssertEqual(short.value as? String, "refreshes:0")
        pullToRefresh(short)
        expectation(for: refreshed, evaluatedWith: short)
        waitForExpectations(timeout: 5)
        attachScreenshot("short-list-refresh")
    }

    @MainActor
    func testHorizontalSwipeEmptyListAndHeaderResize() {
        let app = XCUIApplication()
        app.launch()
        let resize = app.buttons["resizeHeader"]
        XCTAssertTrue(resize.waitForExistence(timeout: 5))
        let oldY = app.buttons["精选"].frame.minY
        resize.tap()
        XCTAssertGreaterThan(app.buttons["精选"].frame.minY, oldY + 50)
        app.tables["list-long"].swipeLeft()
        XCTAssertTrue(app.tables["list-short"].waitForExistence(timeout: 3))
        app.buttons["分类"].tap()
        let empty = app.tables["list-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 3))
        empty.swipeUp()
        XCTAssertLessThan(app.buttons["分类"].frame.minY, oldY)
        empty.swipeDown()
        pullToRefresh(empty)
        let refreshed = NSPredicate(format: "value == %@", "refreshes:1")
        expectation(for: refreshed, evaluatedWith: empty)
        waitForExpectations(timeout: 5)
        attachScreenshot("empty-list")
    }

    @MainActor
    func testSwiftUIHostCanSwipeSwitchAndRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["--swiftui-host"]
        app.launch()
        XCTAssertTrue(app.staticTexts["sharedHeader"].waitForExistence(timeout: 5))
        app.tables["list-long"].swipeLeft()
        let short = app.tables["list-short"]
        XCTAssertTrue(short.waitForExistence(timeout: 3))
        pullToRefresh(short)
        expectation(for: NSPredicate(format: "value == %@", "refreshes:1"), evaluatedWith: short)
        waitForExpectations(timeout: 5)
        app.buttons["精选"].tap()
        XCTAssertTrue(app.tables["list-long"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.tables["list-long"].value as? String, "refreshes:0")
        attachScreenshot("swiftui-host")
    }

    @MainActor
    private func pullToRefresh(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.25)).press(
            forDuration: 0.05,
            thenDragTo: element.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.95))
        )
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
