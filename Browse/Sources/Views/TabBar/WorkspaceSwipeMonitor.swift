import AppKit
import SwiftUI

/// Invisible helper view that watches scroll-wheel events over the sidebar and
/// turns horizontal two-finger swipes on its empty area (not on tab rows) into
/// workspace switches. Deltas are accumulated against a threshold and latched
/// per gesture so a single swipe changes exactly one workspace.
struct WorkspaceSwipeMonitor: NSViewRepresentable {
    /// True while the pointer is over the tab list content; swipes are
    /// ignored there so only the sidebar's empty area triggers switching.
    let isPointerOverTabList: Bool
    let isEnabled: Bool
    /// Live gesture progress in the range -1...1, used to keep the sidebar
    /// content visually attached to the trackpad before a switch commits.
    let onSwipeProgress: (CGFloat) -> Void
    let onSwipeEnd: () -> Void
    /// Fingers moving left (forward): switch to the next workspace.
    let onSwipeLeft: () -> Void
    /// Fingers moving right (backward): switch to the previous workspace.
    let onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(on: view)
        updateCoordinator(context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        updateCoordinator(context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    private func updateCoordinator(_ coordinator: Coordinator) {
        coordinator.isPointerOverTabList = isPointerOverTabList
        coordinator.isEnabled = isEnabled
        coordinator.onSwipeProgress = onSwipeProgress
        coordinator.onSwipeEnd = onSwipeEnd
        coordinator.onSwipeLeft = onSwipeLeft
        coordinator.onSwipeRight = onSwipeRight
    }

    @MainActor
    final class Coordinator {
        var isPointerOverTabList = false
        var isEnabled = false
        var onSwipeProgress: (CGFloat) -> Void = { _ in }
        var onSwipeEnd: () -> Void = {}
        var onSwipeLeft: () -> Void = {}
        var onSwipeRight: () -> Void = {}

        private weak var view: NSView?
        private var monitor: Any?
        private var accumulatedDeltaX: CGFloat = 0
        private var didTriggerForCurrentGesture = false
        private var isTrackingGesture = false
        private var lastPhaselessEventAt: Date = .distantPast
        private var phaselessGestureEndTask: Task<Void, Never>?
        private let swipeThreshold: CGFloat = 42

        func install(on view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            // Local event monitors run on the main thread.
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                let shouldConsume = MainActor.assumeIsolated {
                    self?.handle(event) ?? false
                }
                return shouldConsume ? nil : event
            }
        }

        func uninstall() {
            phaselessGestureEndTask?.cancel()
            phaselessGestureEndTask = nil
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        /// Returns true when the event was handled and should be consumed.
        private func handle(_ event: NSEvent) -> Bool {
            guard isEnabled,
                  let view,
                  let window = view.window,
                  event.window === window else {
                finishGesture()
                return false
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                guard isTrackingGesture else { return false }
                finishGesture()
                return true
            }

            if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
                resetGestureState()
            }

            let locationInView = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(locationInView) else { return false }
            guard !isPointerOverTabList else { return false }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }

            isTrackingGesture = true

            // Ignore inertial scrolling so momentum can't re-trigger a switch.
            guard event.momentumPhase.isEmpty else { return true }

            // Legacy devices deliver no gesture phases; time-box accumulation
            // so distinct swipes don't run together.
            if event.phase.isEmpty {
                if Date().timeIntervalSince(lastPhaselessEventAt) > 0.3 {
                    accumulatedDeltaX = 0
                    didTriggerForCurrentGesture = false
                }
                lastPhaselessEventAt = Date()
                schedulePhaselessGestureEnd()
            }

            if !didTriggerForCurrentGesture {
                accumulatedDeltaX += event.scrollingDeltaX
                onSwipeProgress(max(-1, min(1, accumulatedDeltaX / swipeThreshold)))

                if accumulatedDeltaX <= -swipeThreshold {
                    didTriggerForCurrentGesture = true
                    onSwipeLeft()
                } else if accumulatedDeltaX >= swipeThreshold {
                    didTriggerForCurrentGesture = true
                    onSwipeRight()
                }
            }
            return true
        }

        private func schedulePhaselessGestureEnd() {
            phaselessGestureEndTask?.cancel()
            phaselessGestureEndTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                self?.finishGesture()
            }
        }

        private func finishGesture() {
            phaselessGestureEndTask?.cancel()
            phaselessGestureEndTask = nil
            guard isTrackingGesture else { return }
            onSwipeEnd()
            resetGestureState()
        }

        private func resetGestureState() {
            accumulatedDeltaX = 0
            didTriggerForCurrentGesture = false
            isTrackingGesture = false
        }
    }
}
