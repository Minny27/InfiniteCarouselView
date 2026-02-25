//
//  InfiniteCarouselViewiOS18.swift
//  InfiniteCarouselView
//
//  iOS 18+ implementation of the infinite carousel.
//  Uses ScrollPosition.scrollTo(x:), onScrollPhaseChange, and ScrollPhase
//  — all of which require iOS 18 / macOS 15.
//

import SwiftUI

@available(iOS 18.0, macOS 15.0, *)
struct InfiniteCarouselViewiOS18<T: Identifiable, Content: View>: View {

    // MARK: Inputs

    let items: [T]
    let spacing: CGFloat
    let autoScrollInterval: TimeInterval?
    @Binding var selectedIndex: Int
    @ViewBuilder let content: (T) -> Content

    // MARK: Init

    init(
        items: [T],
        spacing: CGFloat,
        autoScrollInterval: TimeInterval?,
        selectedIndex: Binding<Int>,
        @ViewBuilder content: @escaping (T) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.autoScrollInterval = autoScrollInterval
        self._selectedIndex = selectedIndex
        self.content = content
        // Start at index `count` — the beginning of the real section
        self._displayIndex = State(initialValue: items.count)
        // Pre-initialize currentIndex on the SnapTarget so updateTarget has the
        // correct value before the first render (avoids clamping on early scrolls).
        let st = SnapTarget()
        st.setCurrentIndex(items.count)
        self._snapTarget = State(initialValue: st)
    }

    // MARK: Private State

    /// Current position in the tripled array (0 ..< 3 * count)
    @State private var displayIndex: Int
    @State private var scrollPosition = ScrollPosition()
    @State private var itemSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    /// Tracks scroll phase — used as the task ID to reset the auto-scroll countdown
    @State private var scrollPhase: ScrollPhase = .idle
    /// Shared reference for synchronous communication from updateTarget to onScrollPhaseChange
    @State private var snapTarget: SnapTarget

    // MARK: Computed

    private var count: Int { items.count }
    private var stepWidth: CGFloat { itemSize.width + spacing }
    private var isReady: Bool { itemSize.width > 0 && containerWidth > 0 }

    /// Horizontal padding that centers the first and last cards on screen
    private var horizontalPadding: CGFloat {
        isReady ? (containerWidth - itemSize.width) / 2 : 0
    }

    /// Builds the tripled array — each element has a unique `id` across all three copies
    private var tripledItems: [TripleItem<T>] {
        guard count > 0 else { return [] }
        return (0..<3).flatMap { copy in
            items.enumerated().map { i, item in
                TripleItem(id: copy * count + i, realIndex: i, value: item)
            }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(tripledItems) { triple in
                    content(triple.value)
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: ItemSizeKey.self, value: g.size)
                            }
                        )
                        .onTapGesture { select(triple.id) }
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(
            InfiniteCarouselBehavior(
                stepWidth: stepWidth,
                cardCount: tripledItems.count,
                snapTarget: snapTarget
            )
        )
        .onScrollPhaseChange { _, newPhase in
            scrollPhase = newPhase
            switch newPhase {
            case .decelerating:
                let page = snapTarget.page
                displayIndex = page
                selectedIndex = page % count
                snapTarget.setCurrentIndex(page)
            case .idle:
                loopbackIfNeeded()
            default:
                break
            }
        }
        .onPreferenceChange(ItemSizeKey.self) { size in
            guard size.width > 0, itemSize == .zero else { return }
            itemSize = size
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        )
        .frame(height: itemSize.height > 0 ? itemSize.height : nil)
        .opacity(isReady ? 1 : 0)
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            scrollPosition.scrollTo(x: CGFloat(count) * stepWidth)
        }
        .task(id: scrollPhase) {
            guard let interval = autoScrollInterval,
                  scrollPhase == .idle,
                  isReady else { return }
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            selectNext()
        }
    }

    // MARK: Selection

    private func select(_ index: Int) {
        let clamped = max(0, min(tripledItems.count - 1, index))
        snapTarget.setCurrentIndex(clamped)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            displayIndex = clamped
            selectedIndex = clamped % count
            scrollPosition.scrollTo(x: CGFloat(clamped) * stepWidth)
        }
    }

    private func selectNext() {
        select(displayIndex + 1)
    }

    // MARK: Infinite Loop

    private func loopbackIfNeeded() {
        guard count > 0, stepWidth > 0 else { return }

        if displayIndex < count {
            let newIndex = displayIndex + count
            displayIndex = newIndex
            selectedIndex = newIndex % count
            snapTarget.setCurrentIndex(newIndex)
            scrollPosition.scrollTo(x: CGFloat(newIndex) * stepWidth)
        } else if displayIndex >= 2 * count {
            let newIndex = displayIndex - count
            displayIndex = newIndex
            selectedIndex = newIndex % count
            snapTarget.setCurrentIndex(newIndex)
            scrollPosition.scrollTo(x: CGFloat(newIndex) * stepWidth)
        }
    }
}
