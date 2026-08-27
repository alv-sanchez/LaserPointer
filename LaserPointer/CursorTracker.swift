//
//  CursorTracker.swift
//  LaserPointer
//
//  ============================================================================
//  WHY POLLING, AND NOT AN EVENT MONITOR
//  ============================================================================
//  The obvious way to watch the mouse from another app's window is
//  `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged])`.
//  Two things are wrong with it here:
//
//    1. It requires the Accessibility TCC permission. A presentation pointer
//       asking for "control your computer" access is a disproportionate ask,
//       and — worse — Accessibility is the permission that lets an app read
//       every keystroke you type. This app should never appear in that list.
//
//    2. A global monitor still would not tell us where the cursor is between
//       events, so a slow drag would render as sparse dots anyway.
//
//  `NSEvent.mouseLocation` and `NSEvent.pressedMouseButtons` are both plain
//  reads of window-server state, TCC-gated by nothing, available to any process.
//  Sampling them on a timer gives the same information with no permission
//  prompt, and the cost is two cheap calls per frame.
//
//  The tradeoff is honest: we cannot see a click that begins and ends inside a
//  single sample interval (~8ms). For a laser pointer that is invisible — a
//  mark that brief would be sub-perceptual anyway.
//

import AppKit

@MainActor
final class CursorTracker {

    struct Sample {
        /// Global screen coordinates, bottom-left origin of the main display.
        let location: CGPoint
        /// True while the primary (left) mouse button is held.
        ///
        /// Left button ONLY, masked explicitly. Including the right button would
        /// mean every context menu in the presenting app paints a laser mark.
        let isPressed: Bool
        /// True while the draw modifier is held.
        ///
        /// `NSEvent.modifierFlags` is a plain read of window-server state, like
        /// `mouseLocation` — no permission, no event monitor. That is what makes
        /// the whole gesture design possible.
        let drawModifierHeld: Bool
    }

    /// ========================================================================
    /// WHY DRAWING IS GATED ON A MODIFIER
    /// ========================================================================
    /// The overlay has to SWALLOW the drag it draws from, or the same drag also
    /// selects text in the app underneath. But swallowing cannot be switched on
    /// once a press is already underway: macOS gives the app that received the
    /// `mouseDown` an implicit grab on the rest of the drag, so flipping capture
    /// one sample interval later is far too late — the selection has begun and
    /// keeps going.
    ///
    /// Capture therefore has to be armed BEFORE the button goes down, and a held
    /// modifier is the only thing that reliably says "the next press is for me"
    /// in advance. A human presses ⌥ tens of milliseconds before clicking, so by
    /// the time the `mouseDown` is routed, the overlay is already eligible.
    ///
    /// The payoff is that everything else keeps working while armed — scrolling,
    /// clicking, right-clicking all pass straight through, because the overlay is
    /// click-through whenever ⌥ is not held. The pointer can stay on for a whole
    /// presentation instead of being toggled around every interaction.
    ///
    /// The alternative that allows a bare drag is a CGEventTap, which can swallow
    /// left-drags selectively and pass the rest — at the cost of the Input
    /// Monitoring permission. That trade was considered and declined; see README.
    static let drawModifier: NSEvent.ModifierFlags = .option
    static let drawModifierName = "⌥"

    /// 120 Hz. Matches ProMotion, and costs a rounding error of CPU. Halving it
    /// to 60 is visible as faint stair-stepping on a fast flick.
    private static let interval: TimeInterval = 1.0 / 120.0

    var onSample: ((Sample) -> Void)?

    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }

        // Constructed with `Timer(timeInterval:)` and added to `.common` modes
        // rather than `Timer.scheduledTimer`, which installs in `.default` only.
        // In default mode the timer STOPS FIRING while our own menu-bar dropdown
        // is open — i.e. exactly while the user is dragging the thickness slider
        // and most wants to see the effect.
        let t = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let pressed = (NSEvent.pressedMouseButtons & 0x1) != 0

        // `.deviceIndependentFlagsMask` strips the left/right-hand-key and
        // numeric-pad bits, which are set inconsistently and would make a plain
        // `contains` comparison miss. Other modifiers being held alongside ⌥ is
        // fine — only ⌥'s presence is asked about.
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)

        onSample?(Sample(location: NSEvent.mouseLocation,
                         isPressed: pressed,
                         drawModifierHeld: flags.contains(Self.drawModifier)))
    }
}
