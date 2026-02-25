//
//  ScrollPhaseBackport.swift
//  InfiniteCarouselView
//
//  iOS 17 backport for scroll phase detection.
//  Mirrors the iOS 18 onScrollPhaseChange API using UIScrollView KVO.
//
//  Phase transitions detected via isDragging / isDecelerating KVO.
//  MainActor.assumeIsolated is used for synchronous capture — avoids the
//  async-Task race where intermediate phases are missed.
//

#if canImport(UIKit)
import UIKit
import SwiftUI

// MARK: - Phase Enum

/// Mirrors SwiftUI's ScrollPhase (iOS 18) for use on iOS 17.
enum ScrollPhaseBackport: Equatable, Hashable {
    case idle
    case dragging
    case decelerating
}

// MARK: - KVO Observer

/// Observes a UIScrollView's isDragging / isDecelerating properties via KVO
/// and publishes phase transitions on the main actor.
@MainActor
final class ScrollPhaseKVOObserver: ObservableObject {

    /// Current scroll phase. Published so SwiftUI views can react with onChange(of:).
    @Published private(set) var phase: ScrollPhaseBackport = .idle

    /// The contentOffset.x captured at the moment the most recent phase transition fired.
    /// Use this in an onChange(of: observer.phase) handler to get the offset
    /// without an additional UIScrollView lookup.
    private(set) var lastOffsetX: CGFloat = 0

    private var observations: [NSKeyValueObservation] = []
    private weak var scrollView: UIScrollView?

    // MARK: Attach / Detach

    func attach(to sv: UIScrollView) {
        guard self.scrollView !== sv else { return }
        self.scrollView = sv

        // Use MainActor.assumeIsolated so KVO fires synchronously on the main actor.
        // UIKit guarantees isDragging / isDecelerating KVO fires on the main thread,
        // so this assertion is always valid.
        let obs1 = sv.observe(\.isDragging, options: [.new]) { [weak self, weak sv] _, _ in
            guard let sv else { return }
            MainActor.assumeIsolated { self?.reportPhase(from: sv) }
        }
        let obs2 = sv.observe(\.isDecelerating, options: [.new]) { [weak self, weak sv] _, _ in
            guard let sv else { return }
            MainActor.assumeIsolated { self?.reportPhase(from: sv) }
        }
        observations = [obs1, obs2]
    }

    func detach() {
        observations.removeAll()
        scrollView = nil
    }

    // MARK: Private

    private func reportPhase(from sv: UIScrollView) {
        let newPhase: ScrollPhaseBackport
        if sv.isDragging {
            newPhase = .dragging
        } else if sv.isDecelerating {
            newPhase = .decelerating
        } else {
            newPhase = .idle
        }

        guard newPhase != phase else { return }
        lastOffsetX = sv.contentOffset.x
        phase = newPhase
    }
}

// MARK: - Finder View

/// Invisible UIViewRepresentable that walks the view hierarchy to find the parent
/// UIScrollView and attaches the KVO observer to it.
struct ScrollPhaseObserverView: UIViewRepresentable {
    let observer: ScrollPhaseKVOObserver

    func makeUIView(context: Context) -> FinderView {
        FinderView(observer: observer)
    }

    func updateUIView(_ uiView: FinderView, context: Context) {}

    final class FinderView: UIView {
        private let observer: ScrollPhaseKVOObserver

        init(observer: ScrollPhaseKVOObserver) {
            self.observer = observer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                findAndAttach()
            } else {
                observer.detach()
            }
        }

        private func findAndAttach() {
            var view: UIView? = superview
            while let v = view {
                if let sv = v as? UIScrollView {
                    observer.attach(to: sv)
                    return
                }
                view = v.superview
            }
        }
    }
}

// MARK: - View Modifier (onScrollPhaseBackportChange)

/// Mirrors `View.onScrollPhaseChange` (iOS 18) for iOS 17.
/// Action parameters: (oldPhase, newPhase, contentOffsetX)
private struct ScrollPhaseBackportChangeModifier: ViewModifier {
    @StateObject private var observer = ScrollPhaseKVOObserver()
    let action: (ScrollPhaseBackport, ScrollPhaseBackport, CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .background(ScrollPhaseObserverView(observer: observer))
            .onChange(of: observer.phase) { old, new in
                action(old, new, observer.lastOffsetX)
            }
    }
}

extension View {
    /// Calls `action` whenever the scroll phase transitions, providing the old phase,
    /// new phase, and the contentOffset.x captured at the moment of transition.
    func onScrollPhaseBackportChange(
        _ action: @escaping (ScrollPhaseBackport, ScrollPhaseBackport, CGFloat) -> Void
    ) -> some View {
        modifier(ScrollPhaseBackportChangeModifier(action: action))
    }
}

#endif
