# InfiniteCarouselView

A SwiftUI infinite paging carousel built with the tripling strategy.
Supports auto-scroll, tap-to-page, and swipe-with-spring — all in a single generic view.

---

## Overview

`InfiniteCarouselView` solves the two main problems with infinite carousels in SwiftUI:

**1. Seamless looping without animation glitches**
Items are triplicated internally — `[clone_front | real | clone_back]`.
When the scroll settles in a clone region, the view silently jumps back to the matching position in the real region. Because the content is identical, the user never notices.

```
displayIndex:  0  1  2  3  4 │  5  6  7  8  9 │ 10 11 12 13 14
               [ clone_front ] [     real      ] [  clone_back  ]
selectedIndex: 0  1  2  3  4    0  1  2  3  4    0  1  2  3  4
```

**2. Snappy swipe — no deceleration**
Standard `ScrollTargetBehavior` hands animation control to UIKit, which uses its own deceleration curve.
`InfiniteCarouselView` intercepts the swipe at the `.decelerating` phase transition — before any deceleration frame is rendered — and replaces it with a spring animation identical to the tap behavior.

---

## Requirements

- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

---

## Installation

### Swift Package Manager

In Xcode: **File → Add Package Dependencies**

```
https://github.com/Minny27/InfiniteCarouselView.git
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Minny27/InfiniteCarouselView.git", from: "1.0.0")
]
```

---

## Usage

```swift
import InfiniteCarouselView

struct ContentView: View {
    @State private var selectedIndex = 0

    let items = [
        CardItem(id: 0, title: "First",  color: .orange),
        CardItem(id: 1, title: "Second", color: .blue),
        CardItem(id: 2, title: "Third",  color: .green),
    ]

    var body: some View {
        InfiniteCarouselView(
            items: items,
            spacing: 16,
            autoScrollInterval: 3,   // optional — omit to disable auto-scroll
            selectedIndex: $selectedIndex
        ) { item in
            // Draw your card at any size — InfiniteCarouselView measures it automatically
            RoundedRectangle(cornerRadius: 16)
                .fill(item.color)
                .frame(width: 280, height: 360)
                .overlay {
                    Text(item.title)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }
        }
    }
}
```

### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `items` | `[T: Identifiable]` | — | Data source |
| `spacing` | `CGFloat` | `16` | Gap between cards |
| `autoScrollInterval` | `TimeInterval?` | `nil` | Seconds between auto-advances. `nil` disables auto-scroll |
| `selectedIndex` | `Binding<Int>` | — | Currently centered card index (0-based, real items only) |
| `content` | `@ViewBuilder` | — | Card view. The size of the first rendered card is used as the step width |

---

## How It Works

### Tripling strategy
Three copies of `items` are laid out side by side. Each copy has a unique `id` in the internal array, so SwiftUI never reuses or animates between them.
After every scroll-settle (`onScrollPhaseChange(.idle)`), `loopbackIfNeeded()` checks whether `displayIndex` has entered a clone region and teleports back to the real region at the same visual position.

### Synchronous snap target
`InfiniteCarouselBehavior` (a `ScrollTargetBehavior`) writes the resolved snap page into a shared `SnapTarget` class **synchronously** inside `updateTarget`, and also sets `target.rect.origin.x` so UIKit decelerates to the correct page.
`onScrollPhaseChange(.decelerating)` reads that value in the same run-loop cycle and updates `displayIndex` / `selectedIndex` immediately, while UIKit handles the deceleration animation naturally.

### Auto-scroll timer
The timer uses `.task(id: scrollPhase)`.
Every time `scrollPhase` changes (user touches the screen, programmatic scroll starts, etc.), the task is cancelled and restarted.
This means the countdown always resets after any interaction, and the timer fires only when the scroll has been idle for the full interval.

---

## License

InfiniteCarouselView is released under the MIT License. See [LICENSE](LICENSE) for details.
