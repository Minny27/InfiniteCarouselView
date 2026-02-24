//
//  ScrollPhaseBackport.swift
//  InfiniteCarouselView
//
//  iOS 17 polyfill for onScrollPhaseChange.
//  Observes UIScrollView.isDragging / isDecelerating via KVO to detect scroll phases.
//  Not applicable to macOS (uses NSScrollView internally).
//

#if canImport(UIKit)
import UIKit
import SwiftUI

// MARK: - KVO Observer

/// Observes a UIScrollView's drag/decelerate state and fires callbacks on the main actor.
@MainActor
final class ScrollPhaseKVOObserver: ObservableObject {

    /// Fired when scrolling becomes active (dragging or decelerating starts).
    var onBecomeActive: (() -> Void)?

    /// Fired when scrolling fully stops. Provides the final contentOffset.x
    /// so the caller can compute the snapped page without relying on snapTarget timing.
    var onBecomeIdle: ((CGFloat) -> Void)?

    private var observations: [NSKeyValueObservation] = []
    private weak var scrollView: UIScrollView?
    private var lastWasActive: Bool?

    func attach(to sv: UIScrollView) {
        guard self.scrollView !== sv else { return }
        self.scrollView = sv

        let obs1 = sv.observe(\.isDragging, options: [.new]) { [weak self, weak sv] _, _ in
            Task { @MainActor [weak self, weak sv] in
                guard let sv else { return }
                self?.reportPhase(from: sv)
            }
        }
        let obs2 = sv.observe(\.isDecelerating, options: [.new]) { [weak self, weak sv] _, _ in
            Task { @MainActor [weak self, weak sv] in
                guard let sv else { return }
                self?.reportPhase(from: sv)
            }
        }
        observations = [obs1, obs2]
    }

    func detach() {
        observations.removeAll()
        scrollView = nil
    }

    private func reportPhase(from sv: UIScrollView) {
        let isActive = sv.isDragging || sv.isDecelerating
        guard isActive != lastWasActive else { return }
        lastWasActive = isActive

        if isActive {
            onBecomeActive?()
        } else {
            onBecomeIdle?(sv.contentOffset.x)
        }
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

#endif
