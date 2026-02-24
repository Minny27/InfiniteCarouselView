//
//  InfiniteCarouselBehavior.swift
//  InfiniteCarouselView
//
//  ScrollTargetBehavior that determines the snap target page.
//  - Writes the resolved page to SnapTarget synchronously inside updateTarget
//  - No async callback — onScrollPhaseChange(.decelerating) reads it immediately
//

import SwiftUI

/// Shared reference for passing the snap page from updateTarget to the view synchronously
@MainActor
final class SnapTarget {
    private(set) var page: Int = 0
    func setPage(_ newValue: Int) { page = newValue }
}

struct InfiniteCarouselBehavior: @MainActor ScrollTargetBehavior {
    let stepWidth: CGFloat
    let cardCount: Int
    let currentIndex: Int
    let snapTarget: SnapTarget

    @MainActor
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard stepWidth > 0 else { return }

        let rawPage = target.rect.minX / stepWidth
        let lower = Double(max(0, currentIndex - 1))
        let upper = Double(min(cardCount - 1, currentIndex + 1))
        let page = Int(rawPage.rounded().clamped(to: lower...upper))

        target.rect.origin.x = Double(page) * stepWidth

        // Synchronous write — read in onScrollPhaseChange(.decelerating)
        snapTarget.setPage(page)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
