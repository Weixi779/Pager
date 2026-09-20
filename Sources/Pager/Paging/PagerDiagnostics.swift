//
//  PagerDiagnostics.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 小宇宙. All rights reserved.
//

import OSLog

/// Logs rejected requests without exposing error handling as part of the UI API.
enum PagerDiagnostics {
    private static let logger = Logger(subsystem: "dev.weixi.Pager", category: "Configuration")

    static func reject(_ reason: String) -> Bool {
        logger.error("\(reason, privacy: .public)")
        return false
    }

    static func validate(_ ids: [PagerPageId], selection: PagerPageId?) -> Bool {
        guard Set(ids).count == ids.count else {
            return reject("Page identities must be unique.")
        }
        guard selection == nil || ids.contains(where: { $0 == selection }) else {
            return reject("The selected page must belong to the configured pages.")
        }
        return true
    }
}
