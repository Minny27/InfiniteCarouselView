//
//  InfiniteCarouselView.swift
//  InfiniteCarouselView
//
//  Infinite paging carousel using the tripling strategy.
//  - Items are triplicated: [clone_front | real | clone_back]
//  - On idle, if position is in a clone region, silently jump back to the real region
//  - Item size is measured automatically from the content view via PreferenceKey
//  - autoScrollInterval: when set, advances to the next card every N seconds while idle
//  - Swipe: snap target is written synchronously in updateTarget → read in .decelerating
//           spring fires before any deceleration frame is rendered
//

import SwiftUI

// MARK: - Public View

public struct InfiniteCarouselView<T: Identifiable, Content: View>: View {

    // MARK: Inputs

    private let items: [T]
    private let spacing: CGFloat
    private let autoScrollInterval: TimeInterval?
    @Binding private var selectedIndex: Int
    @ViewBuilder private let content: (T) -> Content

    // MARK: Init

    public init(
        items: [T],
        spacing: CGFloat = 16,
        autoScrollInterval: TimeInterval? = nil,
        selectedIndex: Binding<Int>,
        @ViewBuilder content: @escaping (T) -> Content
    ) {
        self.items = items
        self.spacing = spacing
        self.autoScrollInterval = autoScrollInterval
        self._selectedIndex = selectedIndex
        self.content = content
        let initialRealIndex = Self.clampRealIndex(selectedIndex.wrappedValue, count: items.count)
        let initialDisplayIndex = items.isEmpty ? 0 : items.count + initialRealIndex
        self._displayIndex = State(initialValue: initialDisplayIndex)
        // Pre-initialize currentIndex on the SnapTarget so updateTarget has the
        // correct value before the first render (avoids clamping on early scrolls).
        let st = SnapTarget()
        st.sync(to: initialDisplayIndex)
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
    private var currentRealIndex: Int { Self.clampRealIndex(displayIndex % max(count, 1), count: count) }

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

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(tripledItems) { triple in
                    content(triple.value)
                        // Measure item size on the first layout pass
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(key: ItemSizeKey.self, value: g.size)
                            }
                        )
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
                settleScrollTarget()
            case .idle:
                loopbackIfNeeded()
            default:
                break
            }
        }
        // Capture item size once — ignore subsequent updates
        .onPreferenceChange(ItemSizeKey.self) { size in
            guard size.width > 0, itemSize == .zero else { return }
            itemSize = size
        }
        // Measure container width for horizontalPadding
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { containerWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in containerWidth = w }
            }
        )
        // Match frame height to item height
        .frame(height: itemSize.height > 0 ? itemSize.height : nil)
        // Hide until size is known to prevent layout flash
        .opacity(isReady ? 1 : 0)
        // Scroll to the real section start once both sizes are available
        .onChange(of: isReady) { _, ready in
            guard ready else { return }
            scrollTo(index: displayIndex, animated: false)
        }
        .onChange(of: selectedIndex) { _, newValue in
            syncExternalSelection(to: newValue)
        }
        // Auto-scroll timer.
        // .task(id: scrollPhase) cancels and restarts whenever the phase changes,
        // effectively resetting the countdown after each user interaction.
        .task(id: scrollPhase) {
            guard let interval = autoScrollInterval,
                  scrollPhase == .idle,
                  isReady else { return }
            try? await Task.sleep(for: .seconds(interval))
            // Double-check idle after sleep: another interaction may have arrived
            // in the window between waking up and reaching this line.
            guard !Task.isCancelled, scrollPhase == .idle else { return }
            selectNext()
        }
    }

    // MARK: Selection

    /// Animates to the given index in the tripled array with a spring
    private func select(_ index: Int, animated: Bool = true) {
        guard count > 0 else { return }
        let clamped = clampDisplayIndex(index)
        syncSelectionState(to: clamped)

        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                scrollTo(index: clamped, animated: false)
            }
        } else {
            scrollTo(index: clamped, animated: false)
        }
    }

    private func selectNext() {
        guard count > 0 else { return }
        interruptActiveScrollIfNeeded()
        let next = displayIndex + 1
        guard next < 2 * count else {
            // About to enter the back-clone region.
            // Silently jump to the front-clone equivalent of the current position
            // (same visual — both show the same last card), then animate forward
            // into the real section.  This avoids the back-clone → loopback flash.
            let frontEquiv = displayIndex - count
            select(frontEquiv, animated: false)
            // Defer the animation so SwiftUI processes the silent jump first.
            Task { @MainActor in
                select(frontEquiv + 1)
            }
            return
        }
        select(next)
    }

    private func interruptActiveScrollIfNeeded() {
        guard scrollPhase != .idle else { return }
        scrollTo(index: displayIndex, animated: false)
    }

    // MARK: Infinite Loop

    /// If the current position is in a clone region, instantly jump to the
    /// equivalent position in the real section — no animation, user never sees it.
    private func loopbackIfNeeded() {
        guard count > 0, stepWidth > 0 else { return }

        if displayIndex < count {
            // front clone → real section
            select(displayIndex + count, animated: false)
        } else if displayIndex >= 2 * count {
            // back clone → real section
            select(displayIndex - count, animated: false)
        }
    }

    private func settleScrollTarget() {
        guard count > 0 else { return }
        syncSelectionState(to: clampDisplayIndex(snapTarget.page))
    }

    private func syncExternalSelection(to newValue: Int) {
        guard isReady, count > 0 else { return }
        let realIndex = Self.clampRealIndex(newValue, count: count)
        guard realIndex != currentRealIndex else { return }

        interruptActiveScrollIfNeeded()
        select(count + realIndex)
    }

    private func syncSelectionState(to index: Int) {
        let clamped = clampDisplayIndex(index)
        displayIndex = clamped
        selectedIndex = clamped % count
        snapTarget.sync(to: clamped)
    }

    private func scrollTo(index: Int, animated: Bool) {
        guard stepWidth > 0 else { return }
        let x = CGFloat(index) * stepWidth
        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                scrollPosition.scrollTo(x: x)
            }
        } else {
            scrollPosition.scrollTo(x: x)
        }
    }

    private func clampDisplayIndex(_ index: Int) -> Int {
        guard !tripledItems.isEmpty else { return 0 }
        return max(0, min(tripledItems.count - 1, index))
    }

    private static func clampRealIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(count - 1, index))
    }
}

// MARK: - Internal Types

struct TripleItem<T: Identifiable>: Identifiable {
    let id: Int
    let realIndex: Int
    let value: T
}

private struct ItemSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let new = nextValue()
        if new.width > 0 { value = new }
    }
}

// MARK: - Preview

private struct PreviewItem: Identifiable {
    let id: Int
    let color: Color
    let title: String
}

#Preview {
    let items = [
        PreviewItem(id: 0, color: .orange, title: "First"),
        PreviewItem(id: 1, color: .blue,   title: "Second"),
        PreviewItem(id: 2, color: .green,  title: "Third"),
        PreviewItem(id: 3, color: .purple, title: "Fourth"),
        PreviewItem(id: 4, color: .red,    title: "Fifth"),
    ]

    struct PreviewWrapper: View {
        let items: [PreviewItem]
        @State private var selectedIndex = 0

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    InfiniteCarouselView(
                        items: items,
                        spacing: 16,
                        autoScrollInterval: 3,
                        selectedIndex: $selectedIndex
                    ) { item in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(item.color.opacity(0.8))
                            .frame(width: 260, height: 340)
                            .overlay {
                                Text(item.title)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                            }
                    }

                    Text("Selected: \(selectedIndex)")
                        .foregroundColor(.white)
                }
            }
        }
    }

    return PreviewWrapper(items: items)
}
