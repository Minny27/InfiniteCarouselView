import SwiftUI
import InfiniteCarouselView

// MARK: - Demo Item

private struct DemoItem: Identifiable {
    let id: Int
    let color: Color
    let title: String
}

// MARK: - Content View

struct ContentView: View {

    private let items: [DemoItem] = [
        DemoItem(id: 0, color: .orange, title: "First"),
        DemoItem(id: 1, color: .blue,   title: "Second"),
        DemoItem(id: 2, color: .green,  title: "Third"),
        DemoItem(id: 3, color: .purple, title: "Fourth"),
        DemoItem(id: 4, color: .red,    title: "Fifth"),
    ]

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

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Circle()
                            .fill(i == selectedIndex ? Color.white : Color.gray.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: selectedIndex)
                    }
                }

                Text("Selected: \(selectedIndex)")
                    .foregroundColor(.white)
                    .font(.callout)
            }
        }
    }
}

#Preview {
    ContentView()
}
