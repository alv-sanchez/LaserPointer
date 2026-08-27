# LaserPointer

A macOS menu-bar app that turns your cursor into a presenter's laser pointer:
**hold the mouse button and it draws a glowing mark that fades away behind you.**

Built for reading and presenting — pointing at a line on a slide, tracing a
diagram, drawing attention to a number in a spreadsheet on a screen share.

Personal/local use only. Not notarized, not distributed.

---

## Requires no permissions

This app asks for nothing — no Accessibility, no Input Monitoring, no Screen
Recording — and that is a design constraint rather than an accident. Two
decisions keep it there:

| Needed | Obvious way | What this app does instead |
| --- | --- | --- |
| Cursor position + button state | `NSEvent.addGlobalMonitorForEvents` → **Accessibility** | Samples `NSEvent.mouseLocation` / `pressedMouseButtons` at 120 Hz (`CursorTracker.swift`) |
| A global on/off hotkey | `CGEventTap` → **Input Monitoring** | Carbon `RegisterEventHotKey`, which only ever reports the one chord (`ToggleHotKey.swift`) |

Both alternatives would have meant an app that can read every keystroke you
type. If either file ever gets "modernised" into an event tap, that property is
gone — the reasoning is written out at the top of both.

The only entitlement is the **App Sandbox**: no network, no file access, no
camera or mic.

---

## Usage

| | |
|---|---|
| Toggle on/off | Menu-bar icon, or **⌃⌥⌘L** from anywhere |
| Draw | Hold **⌥** and drag with the primary mouse button |
| Mode | **Trail** (ink that fades behind the cursor) or **Dot only** |
| Color | Red · Green · Cyan · Amber |
| Size / Fade | Sliders — fade is 0.25s to 5s |

Settings persist across launches. The armed state does not: it always starts off,
so the app never begins capturing your mouse because of something you did days
ago.

### Why drawing needs ⌥, and why that is the good outcome

Drawing is a press-and-drag, and the overlay has to *swallow* that drag — if it
passed through, every stroke would also select text or drag something in the app
underneath. But capture cannot be switched on once a press is already underway:
macOS gives the app that received the `mouseDown` an implicit grab on the rest of
the drag, so flipping capture one sample later (~8ms) is far too late. The
selection has already started and keeps going.

So capture has to be armed *before* the click, and a held modifier is the only
thing that says "the next press is mine" in advance. The payoff:

| While armed | Goes to |
|---|---|
| Scroll | **your app** |
| Click, right-click | **your app** |
| Bare drag | **your app** (selects text as normal) |
| **⌥ + drag** | **draws ink** — nothing reaches your app |

Which means you can leave the pointer **armed for a whole presentation** and
still scroll, click and interact normally. Releasing ⌥ mid-stroke ends the
stroke and hands the mouse straight back.

The menu-bar strip of every display always passes clicks through, so the
menu-bar icon stays reachable even mid-gesture — that plus ⌃⌥⌘L are the off
switches. The keyboard is never touched at all, so a presentation clicker still
advances your slides.

**The alternative, declined:** a `CGEventTap` could swallow left-drags
selectively and let a bare drag draw while scroll passes through — at the cost of
the **Input Monitoring** permission, and the no-permissions property above. If
that trade ever looks worth it, the reasoning to overturn is at the top of
`CursorTracker.swift`.

## Presenting over a screen share

The overlay is **not** excluded from screen capture (`sharingType = .readOnly`),
so it shows up in Zoom, Meet, Teams and QuickTime recordings. That is the whole
point — the remote audience is usually the audience that needs the pointer.

It also draws over **full-screen Keynote and PowerPoint slideshows**, which is
why the overlay sits at the shielding window level. Details and the safety
argument for that level are in `LaserOverlayWindow.swift`.

---

## Build

```bash
./build.sh
```

Compiles with `swiftc`, assembles `build/LaserPointer.app`, signs it, and
launches it. No Xcode project and no SwiftPM manifest — one script, ~1000 lines
of Swift, macOS 13+.

`build/` is gitignored; a fresh clone builds a complete app bundle from that one
command.

### Optional: stable signing identity

The script signs ad-hoc if it finds nothing better, which is fine for an app
that needs no permissions. An ad-hoc signature changes on every rebuild, so if
you later add anything that identifies the app by signature (a login item, a
firewall rule, a TCC grant), create a local self-signed certificate named
`LaserPointer Local Signing` in Keychain Access and the script will use it.

---

## Source map

| File | What it owns |
|---|---|
| `LaserPointerApp.swift` | `MenuBarExtra` scene, app delegate, teardown at quit |
| `MenuContentView.swift` | The dropdown; raises itself above the overlay |
| `PointerController.swift` | Runtime: overlays per display, press state machine, mouse-capture policy |
| `CursorTracker.swift` | 120 Hz permission-free cursor + modifier sampling; why the gesture is ⌥-gated |
| `LaserOverlayWindow.swift` | The transparent shielding-level panel, one per display |
| `InkCanvasView.swift` | Drawing: fade curve, four-pass glow, event swallowing |
| `LaserStyle.swift` | Settings model + UserDefaults |
| `ToggleHotKey.swift` | ⌃⌥⌘L via Carbon |

Multi-display works: one overlay per screen, rebuilt on
`didChangeScreenParametersNotification` (plugging into a projector mid-talk), and
a drag that crosses a bezel is split into one stroke per display.
