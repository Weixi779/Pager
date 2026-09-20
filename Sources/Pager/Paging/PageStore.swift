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
    private(set) var controllers: [PagerPageId: UIViewController] = [:]

    static func validate(_ pages: [PagerPage], selection: PagerPageId?) -> Bool {
        PagerDiagnostics.validate(pages.map(\.id), selection: selection)
    }

    func replace(with pages: [PagerPage]) -> [(PagerPageId, UIViewController)] {
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
        controllers[page.id] = controller
        return (controller, true)
    }
}
