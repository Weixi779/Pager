//
//  PagerTabBar.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// A standalone page navigation bar. Taps emit intent; the owner commits selection.
@MainActor
public final class PagerTabBar: UIView {
    public struct Item: Equatable {
        public let id: PagerPageID
        public var title: String
        public var accessibilityLabel: String?

        public init(id: PagerPageID, title: String, accessibilityLabel: String? = nil) {
            self.id = id
            self.title = title
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public struct Configuration {
        public var font = UIFont.preferredFont(forTextStyle: .body)
        public var selectedFont = UIFont.preferredFont(forTextStyle: .headline)
        public var textColor = UIColor.secondaryLabel
        public var selectedTextColor = UIColor.label
        public var indicatorColor = UIColor.label
        public var indicatorHeight: CGFloat = 3
        /// nil follows title width; a nonnegative value fixes the indicator width.
        public var indicatorWidth: CGFloat?
        public var indicatorBottomInset: CGFloat = 0
        public var itemSpacing: CGFloat = 24
        public var horizontalInset: CGFloat = 16
        public var minimumItemWidth: CGFloat = 44
        public var distributesItemsEqually = false
        public init() {}
    }

    public var configuration = Configuration() {
        didSet { updateButtons(); setNeedsLayout() }
    }

    public var onSelect: ((PagerPageID) -> Void)?
    public private(set) var items: [Item] = []
    public private(set) var selectedPageID: PagerPageID?
    private let scrollView = UIScrollView()
    private let indicator = UIView()
    private var buttons: [UIButton] = []
    private var displayedTransition: PagerTransition?

    override public init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.semanticContentAttribute = .forceLeftToRight
        addSubview(scrollView)
        indicator.isUserInteractionEnabled = false
        scrollView.addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setItems(_ items: [Item], selectedPageID: PagerPageID? = nil) throws {
        var ids = Set<PagerPageID>()
        for item in items where !ids.insert(item.id).inserted {
            throw PagerError.duplicatePageID(item.id)
        }
        if let selectedPageID, !ids.contains(selectedPageID) { throw PagerError.unknownPageID(selectedPageID) }
        buttons.forEach { $0.removeFromSuperview() }
        self.items = items
        self.selectedPageID = selectedPageID
        displayedTransition = nil
        buttons = items.enumerated().map { index, item in
            let button = UIButton(type: .custom)
            button.tag = index
            button.setTitle(item.title, for: .normal)
            button.accessibilityLabel = item.accessibilityLabel ?? item.title
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.addTarget(self, action: #selector(didTap(_:)), for: .touchUpInside)
            scrollView.addSubview(button)
            return button
        }
        updateButtons()
        setNeedsLayout()
    }

    public func setSelection(_ id: PagerPageID?) {
        guard id == nil || items.contains(where: { $0.id == id }) else { return }
        selectedPageID = id
        displayedTransition = nil
        updateButtons()
        setNeedsLayout()
        layoutIfNeeded()
        if let index = items.firstIndex(where: { $0.id == id }) {
            scrollView.scrollRectToVisible(buttons[index].frame.insetBy(dx: -configuration.itemSpacing, dy: 0), animated: false)
        }
    }

    public func displayTransition(_ transition: PagerTransition) {
        guard items.contains(where: { $0.id == transition.source }),
              items.contains(where: { $0.id == transition.destination }), transition.progress.isFinite else { return }
        displayedTransition = transition
        setNeedsLayout()
        layoutIfNeeded()
    }

    /// Convenience for consumers forwarding their Pager delegate events.
    public func receive(_ event: PagerEvent) {
        switch event {
        case let .willTransition(value), let .didUpdateTransition(value): displayTransition(value)
        case let .didFinishTransition(value, completed): setSelection(completed ? value.destination : value.source)
        case let .didSelect(id): setSelection(id)
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        let inset = max(0, configuration.horizontalInset)
        let spacing = max(0, configuration.itemSpacing)
        let available = max(0, bounds.width - 2 * inset - CGFloat(max(0, items.count - 1)) * spacing)
        let widths = items.map { item -> CGFloat in
            let title = item.title as NSString
            let textWidth = max(title.size(withAttributes: [.font: configuration.font]).width,
                                title.size(withAttributes: [.font: configuration.selectedFont]).width)
            return max(configuration.minimumItemWidth, ceil(textWidth))
        }
        let equalWidth = max(widths.max() ?? 0, available / CGFloat(max(1, items.count)))
        var x = inset
        for (index, button) in buttons.enumerated() {
            let width = configuration.distributesItemsEqually ? equalWidth : widths[index]
            button.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width + spacing
        }
        scrollView.contentSize = CGSize(width: max(bounds.width, x - (items.isEmpty ? 0 : spacing) + inset), height: bounds.height)
        let fromID = displayedTransition?.source ?? selectedPageID
        let toID = displayedTransition?.destination ?? selectedPageID
        guard let from = indicatorFrame(for: fromID), let to = indicatorFrame(for: toID) else {
            indicator.isHidden = true
            return
        }
        let progress = min(max(displayedTransition?.progress ?? 0, 0), 1)
        indicator.isHidden = configuration.indicatorHeight <= 0
        indicator.frame = CGRect(x: from.minX + (to.minX - from.minX) * progress,
                                 y: from.minY, width: from.width + (to.width - from.width) * progress, height: from.height)
        indicator.backgroundColor = configuration.indicatorColor
        indicator.layer.cornerRadius = indicator.bounds.height / 2
        scrollView.bringSubviewToFront(indicator)
    }

    private func indicatorFrame(for id: PagerPageID?) -> CGRect? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let button = buttons[index]
        let width = max(0, configuration.indicatorWidth ?? (items[index].title as NSString).size(withAttributes: [.font: configuration.selectedFont]).width)
        let height = max(0, configuration.indicatorHeight)
        return CGRect(x: button.frame.midX - width / 2,
                      y: bounds.height - height - configuration.indicatorBottomInset, width: width, height: height)
    }

    private func updateButtons() {
        for (index, button) in buttons.enumerated() {
            let selected = items[index].id == selectedPageID
            button.titleLabel?.font = selected ? configuration.selectedFont : configuration.font
            button.setTitleColor(selected ? configuration.selectedTextColor : configuration.textColor, for: .normal)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }

    @objc private func didTap(_ sender: UIButton) {
        onSelect?(items[sender.tag].id)
    }
}
