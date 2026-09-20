//
//  PageStore.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

@MainActor
final class PageStore {
    private(set) var pages: [PagerPage] = []
    private(set) var controllers: [PagerPageID: UIViewController] = [:]

    static func validate(_ pages: [PagerPage], selection: PagerPageID?) throws {
        var ids = Set<PagerPageID>()
        for page in pages where !ids.insert(page.id).inserted {
            throw PagerError.duplicatePageID(page.id)
        }
        if let selection, !ids.contains(selection) { throw PagerError.unknownPageID(selection) }
    }

    func replace(with pages: [PagerPage]) -> [(PagerPageID, UIViewController)] {
        let ids = Set(pages.map(\.id))
        let removed = controllers.filter { !ids.contains($0.key) }
        for id in removed.keys {
            controllers.removeValue(forKey: id)
        }
        self.pages = pages
        return Array(removed)
    }

    func controller(at index: Int) -> (controller: UIViewController, created: Bool) {
        let page = pages[index]
        if let controller = controllers[page.id] { return (controller, false) }
        let controller = page.makeViewController()
        precondition(controller.parent == nil, "A page factory must return an unparented controller.")
        precondition(!controllers.values.contains { $0 === controller }, "Each page ID needs its own controller.")
        controllers[page.id] = controller
        return (controller, true)
    }
}
