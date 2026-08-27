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
| Draw | Hold the primary mouse button and move |
| Mode | **Trail** (ink that fades behind the cursor) or **Dot only** |
| Color | Red · Green · Cyan · Amber |
| Size / Fade | Sliders — fade is 0.25s to 5s |

Settings persist across launches. The armed state does not: it always starts off,
so the app never begins capturing your mouse because of something you did days
ago.

### While it is armed, your clicks do not reach your apps

This is the part worth knowing. Drawing is a press-and-drag, and if that drag
also reached the app underneath, every stroke would select text, drag a file, or
draw a marquee — so while armed the overlay **swallows mouse input**. It is a
draw mode, not an overlay you can click through.

What still works while armed:

- **The menu bar.** The top strip of every display keeps passing clicks through,
  so the menu-bar icon (and the clock, Wi-Fi, everything else) stays reachable.
  That is the guaranteed off switch.
- **⌃⌥⌘L**, from any app.
- **The keyboard, entirely.** Nothing keyboard-driven is touched — which means a
  presentation clicker still advances your slides, since those send arrow keys.

Scroll wheel and right-click are captured too, for the same reason. If you want
to interact with something, turn the pointer off; that is what the hotkey is for.

---

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
| `CursorTracker.swift` | 120 Hz permission-free cursor sampling |
| `LaserOverlayWindow.swift` | The transparent shielding-level panel, one per display |
| `InkCanvasView.swift` | Drawing: fade curve, four-pass glow, event swallowing |
| `LaserStyle.swift` | Settings model + UserDefaults |
| `ToggleHotKey.swift` | ⌃⌥⌘L via Carbon |

Multi-display works: one overlay per screen, rebuilt on
`didChangeScreenParametersNotification` (plugging into a projector mid-talk), and
a drag that crosses a bezel is split into one stroke per display.
