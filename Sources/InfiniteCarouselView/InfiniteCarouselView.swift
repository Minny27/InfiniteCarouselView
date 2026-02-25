//
//  InfiniteCarouselView.swift
//  InfiniteCarouselView
//
//  Public entry point for the infinite paging carousel.
//  Dispatches to the appropriate platform implementation:
//  - iOS 18+ / macOS 15+: InfiniteCarouselViewiOS18  (ScrollPosition API)
//  - iOS 17:              InfiniteCarouselViewLegacy (scrollPosition(id:) + KVO)
//
//  Strategy: tripling
//  - Items are triplicated: [clone_front | real | clone_back]
//  - On idle, if position is in a clone region, silently jump back to the real region
//  - Tap: tapping an adjacent card pages to it
//  - Swipe: InfiniteCarouselBehavior snaps to the nearest page
//  - autoScrollInterval: advances to the next card every N seconds while idle
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
    }

    // MARK: Body

    public var body: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            InfiniteCarouselViewiOS18(
                items: items,
                spacing: spacing,
                autoScrollInterval: autoScrollInterval,
                selectedIndex: $selectedIndex,
                content: content
            )
        } else {
#if canImport(UIKit)
            InfiniteCarouselViewLegacy(
                items: items,
                spacing: spacing,
                autoScrollInterval: autoScrollInterval,
                selectedIndex: $selectedIndex,
                content: content
            )
#endif
        }
    }
}

// MARK: - Internal Shared Types

/// A single slot in the tripled array.
/// Each copy gets a unique `id` so ForEach and scrollPosition(id:) can address them.
struct TripleItem<T: Identifiable>: Identifiable {
    let id: Int
    let realIndex: Int
    let value: T
}

/// PreferenceKey for measuring item size from within the scroll content.
struct ItemSizeKey: PreferenceKey {
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
