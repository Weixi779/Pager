//
//  ScrollPageHost.swift
//  Pager
//
//  Created by weixi on 2026/9/20.
//  Copyright © 2026 weixi. All rights reserved.
//

import UIKit

/// Owns horizontal geometry and UIKit scroll callbacks, not page retention or VC lifecycle.
@MainActor
final class ScrollPageHost: UIView, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    var onScroll: ((CGFloat) -> Void)?
    var onBeginDragging: (() -> Void)?
    var onSettle: (() -> Void)?
    private var isPositioning = false
    private(set) var pageCount = 0
    private var mounted: [Int: UIView] = [:]
    var pageWidth: CGFloat {
        bounds.width
    }

    var position: CGFloat {
        pageWidth > 0 ? scrollView.contentOffset.x / pageWidth : 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.bounces = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.scrollsToTop = false
        scrollView.contentInsetAdjustmentBehavior = .never
        // Page order is explicitly supplied by the consumer, independent of locale.
        scrollView.semanticContentAttribute = .forceLeftToRight
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        pageCount: Int,
        views: [Int: UIView],
        selectedIndex: Int
    ) {
        self.pageCount = pageCount
        mounted = views
        layoutPages(selectedIndex: selectedIndex)
    }

    func mount(_ view: UIView, at index: Int) {
        mounted[index] = view
        if view.superview !== scrollView { scrollView.addSubview(view) }
        view.frame = CGRect(
            x: CGFloat(index) * pageWidth,
            y: 0,
            width: pageWidth,
            height: bounds.height
        )
    }

    func layoutPages(selectedIndex: Int) {
        isPositioning = true
        scrollView.frame = bounds
        scrollView.contentSize = CGSize(width: pageWidth * CGFloat(pageCount), height: bounds.height)
        for (index, view) in mounted {
            view.frame = CGRect(
                x: CGFloat(index) * pageWidth,
                y: 0,
                width: pageWidth,
                height: bounds.height
            )
        }
        scrollView.setContentOffset(CGPoint(x: CGFloat(selectedIndex) * pageWidth, y: 0), animated: false)
        isPositioning = false
    }

    func move(to index: Int, animated: Bool) {
        scrollView.setContentOffset(CGPoint(x: CGFloat(index) * pageWidth, y: 0), animated: animated)
    }

    func stop() {
        isPositioning = true
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        isPositioning = false
    }

    func scrollViewDidScroll(_: UIScrollView) {
        guard !isPositioning, pageWidth > 0 else { return }
        onScroll?(position)
    }

    func scrollViewWillBeginDragging(_: UIScrollView) {
        onBeginDragging?()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { onSettle?() }
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        onSettle?()
    }

    func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
        onSettle?()
    }
}
