//
//  PointerController.swift
//  LaserPointer
//
//  Owns the whole runtime: the overlay window per display, the cursor sampler,
//  and the press state machine that turns samples into strokes.
//

import AppKit
import Combine

@MainActor
final class PointerController: ObservableObject {

    /// The master switch. Everything expensive — the overlay windows and the
    /// sampling timer — exists only while this is true, so a disabled app is
    /// genuinely idle rather than merely invisible.
    @Published var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            isEnabled ? activate() : deactivate()
        }
    }

    @Published var style: LaserStyle = StyleStore.load() {
        didSet {
            StyleStore.save(style)
            for overlay in overlays { overlay.canvas.style = style }
        }
    }

    private var overlays: [LaserOverlayWindow] = []
    private let tracker = CursorTracker()

    // MARK: - Press state

    private var wasPressed = false

    /// The overlay currently receiving the stroke. Tracked so a drag that
    /// crosses from one display to another can be split into two strokes — a
    /// single stroke cannot span two windows, and without this the ink simply
    /// stopped at the bezel.
    private weak var activeOverlay: LaserOverlayWindow?

    init() {
        tracker.onSample = { [weak self] sample in
            self?.handle(sample)
        }

        // Display topology changes constantly in the situation this app is for:
        // plugging into a projector, unplugging, mirroring on and off. Each of
        // those invalidates every overlay's geometry, so they get rebuilt.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Lifecycle

    func toggle() { isEnabled.toggle() }

    private func activate() {
        rebuildOverlays()
        tracker.start()
    }

    private func deactivate() {
        tracker.stop()
        wasPressed = false
        activeOverlay = nil
        teardownOverlays()
    }

    /// The single teardown path. Must be called before the process exits —
    /// see the note in AppDelegate about why deinit is not good enough.
    func shutdown() {
        tracker.stop()
        teardownOverlays()
    }

    private func teardownOverlays() {
        for overlay in overlays {
            overlay.canvas.clear()
            overlay.orderOut(nil)
        }
        overlays.removeAll()
    }

    @objc private func screensChanged() {
        guard isEnabled else { return }
        rebuildOverlays()
    }

    private func rebuildOverlays() {
        teardownOverlays()
        activeOverlay = nil

        for screen in NSScreen.screens {
            let overlay = LaserOverlayWindow(screen: screen)
            overlay.canvas.style = style
            overlay.show()
            overlays.append(overlay)
        }
    }

    // MARK: - Sampling

    private func handle(_ sample: CursorTracker.Sample) {
        let now = CACurrentMediaTime()
        let target = overlay(containing: sample.location)

        if sample.isPressed {
            let startingFresh = !wasPressed || target !== activeOverlay

            if startingFresh {
                // Close out whatever stroke was open — either the button was up,
                // or the cursor just crossed onto a different display.
                activeOverlay?.canvas.endStroke()
                if let target {
                    target.canvas.beginStroke(at: local(sample.location, in: target), now: now)
                }
                activeOverlay = target
            } else if let target {
                target.canvas.extendStroke(to: local(sample.location, in: target), now: now)
            }
        } else if wasPressed {
            activeOverlay?.canvas.endStroke()
            activeOverlay = nil
        }

        wasPressed = sample.isPressed

        updateMouseCapture(cursor: sample.location)

        // Every canvas advances every frame, not just the active one: ink on the
        // display the cursor just left still has to finish fading out.
        for overlay in overlays {
            overlay.canvas.advance(now: now)
        }
    }

    /// Decides, every frame, which overlays swallow mouse input and which let it
    /// through.
    ///
    /// Capture is what stops a drawing drag from selecting text in the app
    /// underneath. The one exception is the menu-bar strip of whichever display
    /// the cursor is on: clicks there must reach the status item, because that
    /// menu is the off switch. Every other overlay stays in capture mode — the
    /// cursor is not on them, so there is nothing to pass through anyway.
    ///
    /// Done from the sampling tick rather than from a mouse-moved handler because
    /// the decision has to be made BEFORE the click arrives; by the time we could
    /// handle an event over the menu bar, we would already have stolen it.
    private func updateMouseCapture(cursor: CGPoint) {
        for overlay in overlays {
            let frame = overlay.frame
            let inStrip = NSMouseInRect(cursor, frame, false)
                && cursor.y >= frame.maxY - overlay.menuBarStripHeight
            overlay.setPassesThroughMouse(inStrip)
        }
    }

    private func overlay(containing globalPoint: CGPoint) -> LaserOverlayWindow? {
        overlays.first { NSMouseInRect(globalPoint, $0.frame, false) }
    }

    /// Global screen coordinates to view coordinates. A plain subtraction only
    /// because the canvas is unflipped and fills the window exactly — see the
    /// note at the top of InkCanvasView.
    private func local(_ globalPoint: CGPoint, in overlay: LaserOverlayWindow) -> CGPoint {
        CGPoint(x: globalPoint.x - overlay.frame.minX,
                y: globalPoint.y - overlay.frame.minY)
    }
}
