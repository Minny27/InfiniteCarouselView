//
//  InfiniteCarouselBehavior.swift
//  InfiniteCarouselView
//
//  ScrollTargetBehavior that determines the snap target page.
//  - Writes the resolved page to SnapTarget synchronously inside updateTarget
//  - No async callback — onScrollPhaseChange(.decelerating) reads it immediately
//

import SwiftUI

/// Shared reference for synchronous communication between the behavior and the view.
/// Both `page` and `currentIndex` are class-stored so updateTarget always reads
/// the latest value regardless of SwiftUI's render cycle.
@MainActor
final class SnapTarget {
    private(set) var page: Int = 0
    private(set) var currentIndex: Int = 0

    func setPage(_ newValue: Int) { page = newValue }
    func setCurrentIndex(_ newValue: Int) { currentIndex = newValue }
}

struct InfiniteCarouselBehavior: @MainActor ScrollTargetBehavior {
    let stepWidth: CGFloat
    let cardCount: Int
    let snapTarget: SnapTarget

    @MainActor
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard stepWidth > 0 else { return }

        let rawPage = target.rect.minX / stepWidth
        // Read currentIndex from the class reference — always up-to-date even if
        // the view hasn't re-rendered yet (e.g., loopback fires in the same frame).
        let lower = Double(max(0, snapTarget.currentIndex - 1))
        let upper = Double(min(cardCount - 1, snapTarget.currentIndex + 1))
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
