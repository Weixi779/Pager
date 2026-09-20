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
public final class PagerTabBar: UIView, PagerNavigationPresenting {
    public struct Item: Equatable {
        public let id: PagerPageId
        public var title: String
        public var accessibilityLabel: String?

        public init(id: PagerPageId, title: String, accessibilityLabel: String? = nil) {
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

    public var onSelect: ((PagerPageId) -> Void)?
    public private(set) var items: [Item] = []
    public private(set) var selectedPageId: PagerPageId?
    public var pageIds: [PagerPageId] {
        items.map(\.id)
    }

    private let scrollView = UIScrollView()
    private let indicator = UIView()
    private var buttons: [UIButton] = []
    private var displayedTransition: PagerTransition?
    private var needsSelectionReveal = false

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

    /// Returns false without changing items or selection when validation fails.
    @discardableResult
    public func setItems(_ items: [Item], selectedPageId: PagerPageId? = nil) -> Bool {
        guard PagerDiagnostics.validate(items.map(\.id), selection: selectedPageId) else { return false }
        applyValidatedItems(items, selectedPageId: selectedPageId)
        return true
    }

    /// The caller must validate unique identities and membership of the selection.
    func applyValidatedItems(_ items: [Item], selectedPageId: PagerPageId?) {
        buttons.forEach { $0.removeFromSuperview() }
        self.items = items
        self.selectedPageId = selectedPageId
        needsSelectionReveal = true
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

    public func setSelection(_ id: PagerPageId?) {
        guard id == nil || items.contains(where: { $0.id == id }) else { return }
        selectedPageId = id
        needsSelectionReveal = true
        displayedTransition = nil
        updateButtons()
        setNeedsLayout()
        layoutIfNeeded()
    }

    public func displayTransition(_ transition: PagerTransition) {
        guard items.contains(where: { $0.id == transition.source }),
              items.contains(where: { $0.id == transition.destination }), transition.progress.isFinite else { return }
        displayedTransition = transition
        setNeedsLayout()
        layoutIfNeeded()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        if scrollView.bounds.size != bounds.size { needsSelectionReveal = true }
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
        if needsSelectionReveal, bounds.width > 0, bounds.height > 0 {
            needsSelectionReveal = false
            if let index = items.firstIndex(where: { $0.id == selectedPageId }) {
                scrollView.scrollRectToVisible(buttons[index].frame.insetBy(dx: -spacing, dy: 0), animated: false)
            }
        }
        let fromId = displayedTransition?.source ?? selectedPageId
        let toId = displayedTransition?.destination ?? selectedPageId
        guard let from = indicatorFrame(for: fromId), let to = indicatorFrame(for: toId) else {
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

    private func indicatorFrame(for id: PagerPageId?) -> CGRect? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let button = buttons[index]
        let width = max(0, configuration.indicatorWidth ?? (items[index].title as NSString).size(withAttributes: [.font: configuration.selectedFont]).width)
        let height = max(0, configuration.indicatorHeight)
        return CGRect(x: button.frame.midX - width / 2,
                      y: bounds.height - height - configuration.indicatorBottomInset, width: width, height: height)
    }

    private func updateButtons() {
        for (index, button) in buttons.enumerated() {
            let selected = items[index].id == selectedPageId
            button.titleLabel?.font = selected ? configuration.selectedFont : configuration.font
            button.setTitleColor(selected ? configuration.selectedTextColor : configuration.textColor, for: .normal)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }

    @objc private func didTap(_ sender: UIButton) {
        onSelect?(items[sender.tag].id)
    }
}
