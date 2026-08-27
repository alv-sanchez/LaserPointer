//
//  InkCanvasView.swift
//  LaserPointer
//
//  The thing that actually draws. One instance per display, filling that
//  display's overlay window.
//
//  Coordinates: this view is NOT flipped, so its origin is bottom-left — the
//  same convention as `NSEvent.mouseLocation`. That is the whole reason the
//  conversion from a global cursor position to a view position is a plain
//  subtraction of the window origin and nothing more. Do not set `isFlipped`.
//

import AppKit

final class InkCanvasView: NSView {

    /// One sampled position and the moment it was laid down. The birth time is
    /// what drives the fade, so it is captured at sample time and never
    /// recomputed.
    private struct Node {
        let point: CGPoint
        let birth: CFTimeInterval
    }

    // MARK: - State

    private var strokes: [[Node]] = []

    /// Index into `strokes` of the stroke currently being extended, if the
    /// button is down. Nil between presses.
    private var openStroke: Int?

    /// Where the glowing dot sits right now, or nil when nothing is pressed.
    private var live: CGPoint?

    /// The union of everything drawn on the previous frame. Needed because when
    /// ink fades out or the cursor moves away, the pixels it used to occupy must
    /// be invalidated too — invalidating only the NEW content leaves a trail of
    /// stale glow permanently burned into the window.
    private var lastDirty: NSRect = .zero

    var style = LaserStyle()

    override var isOpaque: Bool { false }

    /// A dragged cursor generates far more samples than the ink needs. Dropping
    /// sub-pixel movement keeps stroke arrays short without any visible loss.
    private static let minimumSampleDistance: CGFloat = 0.75

    // MARK: - Input

    func beginStroke(at point: CGPoint, now: CFTimeInterval) {
        strokes.append([Node(point: point, birth: now)])
        openStroke = strokes.count - 1
        live = point
    }

    func extendStroke(to point: CGPoint, now: CFTimeInterval) {
        live = point

        guard let i = openStroke, i < strokes.count else {
            // The open stroke was pruned out from under us (a very slow drag
            // whose oldest nodes aged out entirely). Start a fresh one rather
            // than dropping the sample.
            beginStroke(at: point, now: now)
            return
        }
        guard let last = strokes[i].last else { return }
        guard hypot(point.x - last.point.x, point.y - last.point.y) >= Self.minimumSampleDistance else { return }

        strokes[i].append(Node(point: point, birth: now))
    }

    func endStroke() {
        openStroke = nil
        live = nil
    }

    /// Drops everything immediately — used when the app is disabled or the
    /// display configuration changes underneath us.
    func clear() {
        strokes.removeAll()
        openStroke = nil
        live = nil
        invalidate(.zero)
    }

    // MARK: - Frame advance

    /// Ages out dead ink and schedules the redraw.
    ///
    /// - Returns: true while this canvas still has something to show, so the
    ///   controller can tell whether anything at all is on screen.
    @discardableResult
    func advance(now: CFTimeInterval) -> Bool {
        let cutoff = now - style.fade

        if !strokes.isEmpty {
            // Nodes are appended in time order, so the survivors are always a
            // suffix — no need to filter the whole array.
            for i in strokes.indices {
                if let firstAlive = strokes[i].firstIndex(where: { $0.birth > cutoff }) {
                    if firstAlive > 0 { strokes[i].removeFirst(firstAlive) }
                } else {
                    strokes[i].removeAll()
                }
            }

            // Compacting shifts indices, so the open stroke has to be re-found.
            // It is by definition the last one, which is why tracking it as an
            // index survives this at all.
            let hadOpen = openStroke != nil
            strokes.removeAll { $0.isEmpty }
            openStroke = hadOpen && !strokes.isEmpty ? strokes.count - 1 : nil
        }

        let content = contentBounds()
        invalidate(content)
        return !content.isEmpty
    }

    /// Bounding box of every mark plus the live dot, inflated by the glow radius
    /// so the soft edges are never clipped.
    private func contentBounds() -> NSRect {
        var box: NSRect = .zero
        var hasAny = false

        func absorb(_ p: CGPoint) {
            let r = NSRect(x: p.x, y: p.y, width: 0, height: 0)
            box = hasAny ? box.union(r) : r
            hasAny = true
        }

        if style.mode == .trail {
            for stroke in strokes {
                for node in stroke { absorb(node.point) }
            }
        }
        if let live { absorb(live) }

        guard hasAny else { return .zero }
        // Widest pass is the halo at 3x thickness, plus the dot's 2.6x radius.
        return box.insetBy(dx: -style.thickness * 3.5, dy: -style.thickness * 3.5)
    }

    private func invalidate(_ rect: NSRect) {
        // Union with the previous frame's box, then clip to bounds — a stroke
        // that ran off the edge of the display would otherwise produce a dirty
        // rect larger than the view, which AppKit ignores wholesale.
        let dirty = rect.isEmpty ? lastDirty : (lastDirty.isEmpty ? rect : rect.union(lastDirty))
        lastDirty = rect

        guard !dirty.isEmpty else { return }
        setNeedsDisplay(dirty.intersection(bounds))
    }

    // MARK: - Event consumption

    /// ========================================================================
    /// These overrides are the whole point of the mouse capture, and they work
    /// by doing NOTHING.
    /// ========================================================================
    /// An event delivered to this view has already been taken away from the app
    /// underneath — that is what stops a drawing drag from selecting text in
    /// Keynote, Preview, or a browser. Handling it here and not calling super
    /// ends the event's life: `NSResponder`'s default implementation would pass
    /// it up our own responder chain, where it is discarded anyway, but being
    /// explicit documents that swallowing is intended rather than accidental.
    ///
    /// The ink itself does NOT come from these events — it comes from cursor
    /// sampling in CursorTracker, which keeps working over the menu-bar strip
    /// where capture is deliberately relaxed. Do not start drawing from here;
    /// the two paths would fight over stroke ownership.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Without this, the first click after another app was frontmost is
        // consumed as an activation click and never reaches the view — the very
        // first stroke of a presentation would leak through as a selection.
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let now = CACurrentMediaTime()
        let beam = style.color.color

        if style.mode == .trail {
            drawInk(ctx, now: now, beam: beam)
        }
        if let live {
            drawDot(ctx, at: live, beam: beam)
        }
    }

    /// Four stacked passes per segment: a wide dim halo, a mid glow, the beam
    /// body, and a thin near-white core. That layering is what reads as "lit"
    /// rather than "a coloured line" — a single stroke pass looks like marker
    /// pen no matter what alpha it is given.
    ///
    /// Passes are the outer loop so each width/alpha family is set once per
    /// pass rather than once per segment.
    private func drawInk(_ ctx: CGContext, now: CFTimeInterval, beam: NSColor) {
        let passes: [(width: CGFloat, alpha: CGFloat, color: NSColor)] = [
            (style.thickness * 3.0,  0.14, beam),
            (style.thickness * 1.8,  0.34, beam),
            (style.thickness,        0.95, beam),
            (style.thickness * 0.34, 0.85, .white),
        ]

        for pass in passes {
            ctx.setLineWidth(pass.width)

            for stroke in strokes {
                if stroke.count == 1 {
                    // A tap with no drag: draw the single node as a dot so a
                    // click still leaves a mark.
                    let node = stroke[0]
                    let a = fadeAlpha(node.birth, now: now) * pass.alpha
                    guard a > 0.004 else { continue }
                    ctx.setFillColor(pass.color.withAlphaComponent(a).cgColor)
                    let r = pass.width / 2
                    ctx.fillEllipse(in: CGRect(x: node.point.x - r, y: node.point.y - r,
                                               width: r * 2, height: r * 2))
                    continue
                }

                for i in 1..<stroke.count {
                    // Keyed off the OLDER endpoint, so a segment is never more
                    // opaque than the ink it grows out of.
                    let a = fadeAlpha(stroke[i - 1].birth, now: now) * pass.alpha
                    guard a > 0.004 else { continue }

                    ctx.setStrokeColor(pass.color.withAlphaComponent(a).cgColor)
                    ctx.beginPath()
                    ctx.move(to: stroke[i - 1].point)
                    ctx.addLine(to: stroke[i].point)
                    ctx.strokePath()
                }
            }
        }
    }

    /// The dot under the cursor: a radial falloff for the bloom, then a hard
    /// white-hot centre.
    private func drawDot(_ ctx: CGContext, at point: CGPoint, beam: NSColor) {
        let radius = style.thickness * 2.6

        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                beam.withAlphaComponent(0.80).cgColor,
                beam.withAlphaComponent(0.34).cgColor,
                beam.withAlphaComponent(0.00).cgColor,
            ] as CFArray,
            locations: [0.0, 0.45, 1.0]
        ) {
            ctx.saveGState()
            ctx.drawRadialGradient(gradient,
                                   startCenter: point, startRadius: 0,
                                   endCenter: point, endRadius: radius,
                                   options: [])
            ctx.restoreGState()
        }

        let core = style.thickness * 0.55
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - core, y: point.y - core,
                                   width: core * 2, height: core * 2))
    }

    /// Eased fade. The exponent matters: a linear ramp reads as the ink getting
    /// muddy, because perceived brightness is not linear in alpha. Above 1 the
    /// mark holds its colour and then leaves quickly, which is what a laser
    /// afterimage looks like.
    private func fadeAlpha(_ birth: CFTimeInterval, now: CFTimeInterval) -> CGFloat {
        let age = now - birth
        guard age > 0 else { return 1 }
        guard age < style.fade else { return 0 }
        return pow(1 - CGFloat(age / style.fade), 1.5)
    }
}
