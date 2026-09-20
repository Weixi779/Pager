//
//  PagerDemoHost.swift
//  PagerDemo
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import SwiftUI

/// Example-only bridge: the core package remains UIKit and does not own SwiftUI state.
struct PagerDemoHost: UIViewControllerRepresentable {
    func makeUIViewController(context _: Context) -> DemoViewController {
        DemoViewController()
    }

    func updateUIViewController(_: DemoViewController, context _: Context) {}
}
