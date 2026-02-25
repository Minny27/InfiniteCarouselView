//
//  InfiniteCarouselViewLegacy.swift
//  InfiniteCarouselView
//
//  iOS 17 implementation of the infinite carousel.
//  Mirrors InfiniteCarouselViewiOS18 but uses APIs available on iOS 17:
//  - scrollPosition(id:anchor:) instead of ScrollPosition.scrollTo(x:)
//  - ScrollPhaseKVOObserver (UIScrollView KVO) instead of onScrollPhaseChange
//  - SnapTarget.currentIndex hotfix prevents loopback bounce
//
//  Auto-scroll task uses AutoScrollID(phase:isReady:) as its ID so that
//  the task restarts both when the phase changes AND when the view first
//  becomes ready — working around the "first launch" gap where scrollPhase
//  stays .idle but isReady transitions false → true.
//

#if canImport(UIKit)
import SwiftUI

// MARK: - Auto-scroll Task ID

private struct AutoScrollID: Equatable {
    let phase: ScrollPhaseBackport
    let isReady: Bool
}

// MARK: - Legacy View

struct InfiniteCarouselViewLegacy<T: Identifiable, Content: View>: View {

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
        self._displayIndex = State(initialValue: items.count)
        let st = SnapTarget()
        st.setCurrentIndex(items.count)
        self._snapTarget = State(initialValue: st)
    }

    // MARK: Private State

    @StateObject private var phaseObserver = ScrollPhaseKVOObserver()

    /// Current position in the tripled array (0 ..< 3 * count)
    @State private var displayIndex: Int
    /// Binding that drives scrollPosition(id:anchor:) for programmatic scrolling
    @State private var scrollTarget: Int?
    @State private var itemSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    /// Mirrors phaseObserver.phase — used as auto-scroll task ID
    @State private var scrollPhase: ScrollPhaseBackport = .idle
    @State private var snapTarget: SnapTarget

    // MARK: Computed

    private var count: Int { items.count }
    private var stepWidth: CGFloat { itemSize.width + spacing }
    private var isReady: Bool { itemSize.width > 0 && containerWidth > 0 }

    private var horizontalPadding: CGFloat {
        isReady ? (containerWidth - itemSize.width) / 2 : 0
    }

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
                        // Tag each item so scrollPosition(id:) can find it
                        .id(triple.id)
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
        // Programmatic scroll target — centering the item with the given id
        .scrollPosition(id: $scrollTarget, anchor: .center)
        .scrollTargetBehavior(
            InfiniteCarouselBehavior(
                stepWidth: stepWidth,
                cardCount: tripledItems.count,
                snapTarget: snapTarget
            )
        )
        // Inject the KVO observer into the scroll view hierarchy
        .background(ScrollPhaseObserverView(observer: phaseObserver))
        // React to phase transitions — mirrors onScrollPhaseChange on iOS 18
        .onChange(of: phaseObserver.phase) { old, new in
            scrollPhase = new
            switch new {
            case .decelerating:
                // updateTarget already ran synchronously before isDecelerating flipped,
                // so snapTarget.page is the correct snapped page.
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
        // Scroll to the real section start once both sizes are available
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            scrollTarget = count
        }
        // Auto-scroll timer.
        // AutoScrollID covers both phase changes AND the first isReady transition,
        // avoiding the "first launch" gap where scrollPhase stays .idle but
        // isReady changes false → true without re-triggering the task.
        .task(id: AutoScrollID(phase: scrollPhase, isReady: isReady)) {
            guard let interval = autoScrollInterval,
                  scrollPhase == .idle,
                  isReady else { return }
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            selectNext()
        }
    }

    // MARK: Selection

    /// Animates to the given index in the tripled array.
    /// scrollPosition(id:anchor:) respects withAnimation, so spring works here.
    private func select(_ index: Int) {
        let clamped = max(0, min(tripledItems.count - 1, index))
        snapTarget.setCurrentIndex(clamped)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            scrollTarget = clamped
            displayIndex = clamped
            selectedIndex = clamped % count
        }
    }

    private func selectNext() {
        select(displayIndex + 1)
    }

    // MARK: Infinite Loop

    /// If the current position is in a clone region, instantly jump to the
    /// equivalent position in the real section — no animation, user never sees it.
    private func loopbackIfNeeded() {
        guard count > 0, stepWidth > 0 else { return }

        if displayIndex < count {
            let newIndex = displayIndex + count
            displayIndex = newIndex
            selectedIndex = newIndex % count
            snapTarget.setCurrentIndex(newIndex)
            scrollTarget = newIndex          // no withAnimation → instant jump
        } else if displayIndex >= 2 * count {
            let newIndex = displayIndex - count
            displayIndex = newIndex
            selectedIndex = newIndex % count
            snapTarget.setCurrentIndex(newIndex)
            scrollTarget = newIndex          // no withAnimation → instant jump
        }
    }
}

#endif
