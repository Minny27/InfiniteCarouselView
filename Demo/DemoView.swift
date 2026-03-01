import SwiftUI
import InfiniteCarouselView

// MARK: - Data Model

struct DemoSlide: Identifiable {
    let id: Int
    let imageID: Int
    let accentColor: Color
}

private let slides: [DemoSlide] = [
    .init(id: 0, imageID: 10,  accentColor: .purple),
    .init(id: 1, imageID: 20,  accentColor: .orange),
    .init(id: 2, imageID: 30,  accentColor: .teal),
    .init(id: 3, imageID: 40,  accentColor: .pink),
    .init(id: 4, imageID: 50,  accentColor: .blue),
]

// MARK: - Main View

struct DemoView: View {
    @State private var selectedIndex = 0

    var body: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width - 80
            let cardHeight = cardWidth * 450 / 800

            ZStack {
                LinearGradient(
                    colors: [slides[selectedIndex].accentColor.opacity(0.15), Color(.sRGBLinear, white: 0.97, opacity: 1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: selectedIndex)

                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 4) {
                        Text("InfiniteCarouselView")
                            .font(.title2.bold())
                        Text("Swift Package Demo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 52)
                    .padding(.bottom, 28)

                    // Carousel
                    InfiniteCarouselView(
                        items: slides,
                        spacing: 14,
                        autoScrollInterval: 2.5,
                        selectedIndex: $selectedIndex
                    ) { slide in
                        SlideCardView(slide: slide, width: cardWidth, height: cardHeight)
                    }

                    // Page indicator
                    HStack(spacing: 6) {
                        ForEach(slides.indices, id: \.self) { i in
                            Capsule()
                                .fill(
                                    i == selectedIndex
                                        ? slides[selectedIndex].accentColor
                                        : Color.secondary.opacity(0.3)
                                )
                                .frame(width: i == selectedIndex ? 22 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedIndex)
                        }
                    }
                    .padding(.top, 20)

                    Text("Card \(selectedIndex + 1) of \(slides.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 10)

                    Spacer()
                }
            }
        }
    }
}

// MARK: - Card View

struct SlideCardView: View {
    let slide: DemoSlide
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncImage(url: URL(string: "https://picsum.photos/id/\(slide.imageID)/800/450")) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if phase.error != nil {
                Color.gray
            } else {
                Color(.systemGray5)
                    .overlay(ProgressView())
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

// MARK: - Preview

#Preview {
    DemoView()
}
