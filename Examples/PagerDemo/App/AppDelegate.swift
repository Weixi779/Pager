//
//  AppDelegate.swift
//  PagerDemo
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import Pager
import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo _: UISceneSession, options _: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        if ProcessInfo.processInfo.arguments.contains("--swiftui-host") {
            window.rootViewController = UIHostingController(rootView: PagerDemoHost())
        } else {
            window.rootViewController = DemoViewController()
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class DemoViewController: UIViewController {
    private var sticky: StickyPagerViewController!
    private var tallHeader = false
    private var configuredInitialState = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let header = UIView()
        header.backgroundColor = .secondarySystemBackground
        let title = UILabel()
        title.text = "共享头部"
        title.font = .preferredFont(forTextStyle: .largeTitle)
        title.accessibilityIdentifier = "sharedHeader"
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)
        let resize = UIButton(type: .system)
        resize.setTitle("变更头部高度", for: .normal)
        resize.accessibilityIdentifier = "resizeHeader"
        resize.addTarget(self, action: #selector(resizeHeader), for: .touchUpInside)
        resize.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(resize)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: header.topAnchor, constant: 36),
            resize.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            resize.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
        ])
        let descriptors: [(String, String, Int)] = [("long", "精选", 100), ("short", "发现", 2), ("empty", "分类", 0)]
        do {
            sticky = try StickyPagerViewController(
                pages: descriptors.map { id, _, count in
                    PagerPage(id: PagerPageID(id)) { DemoListViewController(id: id, rowCount: count) }
                },
                items: descriptors.map { .init(id: PagerPageID($0.0), title: $0.1) },
                headerView: header, headerHeight: 200,
                scrollViewProvider: { _, controller in (controller as! DemoListViewController).tableView }
            )
        } catch { preconditionFailure("Invalid demo pages: \(error)") }
        sticky.tabBar.backgroundColor = .systemBackground
        var configuration = PagerTabBar.Configuration()
        configuration.selectedFont = .boldSystemFont(ofSize: 22)
        configuration.font = .systemFont(ofSize: 22)
        configuration.indicatorWidth = 20
        sticky.tabBar.configuration = configuration
        addChild(sticky)
        view.addSubview(sticky.view)
        sticky.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sticky.view.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !configuredInitialState else { return }
        configuredInitialState = true
        if ProcessInfo.processInfo.arguments.contains("--start-pinned"),
           let list = sticky.pager.currentViewController as? DemoListViewController {
            list.tableView.contentOffset.y = -sticky.tabBarHeight
        }
    }

    @objc private func resizeHeader() {
        tallHeader.toggle()
        sticky.setHeaderHeight(tallHeader ? 280 : 200)
    }
}

final class DemoListViewController: UITableViewController {
    private let pageID: String
    private let rowCount: Int
    private var refreshCount = 0

    init(id: String, rowCount: Int) {
        pageID = id
        self.rowCount = rowCount
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "list-" + pageID
        tableView.rowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        let refresh = UIRefreshControl()
        refresh.accessibilityIdentifier = "refresh-" + pageID
        refresh.addTarget(self, action: #selector(refreshCurrentPage), for: .valueChanged)
        refreshControl = refresh
        updateRefreshStatus()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        rowCount
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "\(pageID) · 第 \(indexPath.row + 1) 行"
        content.secondaryText = "刷新 \(refreshCount) 次"
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "\(pageID)-row-\(indexPath.row)"
        return cell
    }

    @objc private func refreshCurrentPage() {
        refreshCount += 1
        updateRefreshStatus()
        tableView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshControl?.endRefreshing() }
    }

    private func updateRefreshStatus() {
        tableView.accessibilityValue = "refreshes:\(refreshCount)"
    }
}
