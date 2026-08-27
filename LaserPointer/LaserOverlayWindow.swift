//
//  LaserOverlayWindow.swift
//  LaserPointer
//
//  One transparent, click-through panel per display, carrying an InkCanvasView.
//

import AppKit

/// ============================================================================
/// WINDOW LEVEL AND MOUSE CAPTURE — read this before changing either
/// ============================================================================
/// This window sits at the shielding level, i.e. above essentially everything
/// including the menu bar and full-screen presentation windows, and while the
/// pointer is armed it CAPTURES mouse input rather than passing it through.
/// Both are deliberate, and the two decisions are linked.
///
/// Why the level: Keynote and PowerPoint put their slideshow windows at the
/// shielding level themselves. An annotation overlay below that level is
/// invisible for the entire activity this app exists for.
///
/// Why capture: the drawing gesture is a press-and-drag. If the overlay let
/// that drag through to the app underneath, every stroke would also be a
/// text selection, a drag-and-drop, or a marquee in the presenting app —
/// which is exactly the bug this capture fixes. Swallowing the drag is the
/// only way to make press-to-draw safe; there is no API to observe a drag
/// without either receiving it or asking for Accessibility.
///
/// Mouse capture is scoped, not absolute:
///
///   * It exists only while armed. Disabled, there are no overlay windows at
///     all, so there is nothing to capture with.
///
///   * The menu-bar strip always passes through (`menuBarStripHeight`), so the
///     status item — and the clock, Wi-Fi, everything else up there — stays
///     clickable while armed. That is the guaranteed off switch, and it is why
///     capture at this level is not a lockout. The ⌃⌥⌘L hotkey is the second
///     exit, and Force Quit the third.
///
///   * Our own dropdown is raised ABOVE this window when it opens (see
///     WindowAccessor in MenuContentView) so its controls receive their own
///     clicks instead of being covered by the overlay.
///
/// The clickjacking concern that normally rules out high-level windows does not
/// apply: this window never renders anything opaque, and it never forwards or
/// synthesises an event. It cannot put a fake control in front of a real one,
/// nor redirect a click onto a hidden button — the worst it can do is decline
/// to let a click reach whatever is beneath it, in a mode the user turned on.
///
/// (For contrast: EDRBoost deliberately caps its overlay at `.floating`, because
/// that overlay paints full-screen opaque bright content. Different content,
/// different answer. Do not copy this level into a window that draws anything
/// solid.)
final class LaserOverlayWindow: NSPanel {

    let canvas = InkCanvasView()

    /// Held explicitly rather than read back from `NSWindow.screen`, which
    /// returns nil for a window that is not on screen yet — including during
    /// init, when the geometry is being set up.
    let targetScreen: NSScreen

    init(screen: NSScreen) {
        self.targetScreen = screen

        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        // Armed means capturing: a press-drag must not reach the app underneath
        // or it selects text there. The controller relaxes this per-frame over
        // the menu-bar strip — see setPassesThroughMouse.
        ignoresMouseEvents = false

        // `.nonactivatingPanel` + these two keep focus where it belongs: clicking
        // around never brings LaserPointer forward, and the panel does not
        // vanish when the presenting app takes over.
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        isMovable = false
        isRestorable = false

        // `.canJoinAllSpaces` + `.fullScreenAuxiliary` are what let the overlay
        // survive a Space switch and appear over a full-screen slideshow.
        // `.stationary` stops Mission Control from animating it around.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        // NOT set to `.none`. Excluding the window from screen capture would
        // hide the pointer from exactly the audience that needs to see it — a
        // Zoom/Meet screen share is the most common way this app gets used.
        sharingType = .readOnly

        canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
        canvas.autoresizingMask = [.width, .height]
        contentView = canvas
    }

    /// The height at the top of this display that must keep passing clicks
    /// through, so the menu bar stays usable while armed.
    ///
    /// Derived from the actual menu bar inset (`frame.maxY - visibleFrame.maxY`),
    /// which is correct for both the notch and the plain 25pt bar, and 0 on a
    /// secondary display that has no menu bar of its own.
    ///
    /// Floored at 24 on purpose. With "automatically hide and show the menu bar"
    /// enabled the inset reads 0, and honouring that literally would leave no
    /// way to reach the status item while armed. The cost of the floor is small
    /// and bounded: in the top 24pt of a display a drag is not captured, so it
    /// may select text underneath — drawing there still works, because the ink
    /// comes from cursor sampling and not from these events.
    var menuBarStripHeight: CGFloat {
        max(targetScreen.frame.maxY - targetScreen.visibleFrame.maxY, 24)
    }

    /// Toggles capture. Assignment is guarded because this is called at 120 Hz
    /// and `ignoresMouseEvents` is a window-server round trip.
    func setPassesThroughMouse(_ passThrough: Bool) {
        guard ignoresMouseEvents != passThrough else { return }
        ignoresMouseEvents = passThrough
    }

    /// Borderless windows are non-key by default, which would prevent the panel
    /// from ever showing. It never accepts input, so key-ness costs nothing —
    /// but `canBecomeKey` stays false so we never steal focus from the
    /// presenting app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        setFrame(targetScreen.frame, display: false)
        orderFrontRegardless()
    }
}
