//
//  MenuContentView.swift
//  LaserPointer
//
//  The menu-bar dropdown. `.menuBarExtraStyle(.window)` is what lets this be
//  real SwiftUI with sliders in it — the default `.menu` style renders NSMenu
//  items and cannot host arbitrary controls.
//

import SwiftUI
import AppKit

struct MenuContentView: View {

    @ObservedObject var controller: PointerController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Toggle(isOn: $controller.isEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Laser pointer")
                        .font(.system(size: 13, weight: .semibold))
                    // The gesture has to be stated, because a bare drag
                    // deliberately does nothing — see CursorTracker for why
                    // capture must be armed before the press.
                    Text("Hold \(CursorTracker.drawModifierName) and drag to draw")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            // Everything below only does something while the pointer is on, so
            // it dims as a set rather than each control explaining itself.
            Group {
                labelled("Mode") {
                    Picker("", selection: $controller.style.mode) {
                        ForEach(LaserMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                labelled("Color") {
                    HStack(spacing: 8) {
                        ForEach(LaserColor.allCases) { option in
                            Swatch(option: option, selected: controller.style.color == option) {
                                controller.style.color = option
                            }
                        }
                        Spacer()
                    }
                }

                labelled("Size") {
                    Slider(value: bind(\.thickness), in: doubleRange(LaserStyle.thicknessRange))
                }

                labelled(String(format: "Fade %.1fs", controller.style.fade)) {
                    Slider(value: $controller.style.fade, in: LaserStyle.fadeRange)
                }
            }
            .disabled(!controller.isEnabled)
            .opacity(controller.isEnabled ? 1 : 0.45)

            Divider()

            HStack {
                Text("Draw \(CursorTracker.drawModifierName)+drag · Toggle \(ToggleHotKey.displayName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(DropdownLevelRaiser())
    }

    // MARK: - Bits

    @ViewBuilder
    private func labelled<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// SwiftUI's Slider is Double-only, and `thickness` is a CGFloat because
    /// every drawing call downstream wants one. Bridged here rather than making
    /// the model store a Double and cast at every use site.
    private func bind(_ path: WritableKeyPath<LaserStyle, CGFloat>) -> Binding<Double> {
        Binding(
            get: { Double(controller.style[keyPath: path]) },
            set: { controller.style[keyPath: path] = CGFloat($0) }
        )
    }

    private func doubleRange(_ range: ClosedRange<CGFloat>) -> ClosedRange<Double> {
        Double(range.lowerBound)...Double(range.upperBound)
    }
}

/// A color dot that shows what the beam will actually look like — same hue and
/// same white-hot centre as the real thing, so the choice is made by eye.
private struct Swatch: View {
    let option: LaserColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: option.color))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 6, height: 6)
                )
                .overlay(
                    Circle()
                        .strokeBorder(.primary.opacity(selected ? 0.9 : 0), lineWidth: 2)
                        .padding(-3)
                )
                .shadow(color: Color(nsColor: option.color).opacity(0.6), radius: selected ? 5 : 0)
        }
        .buttonStyle(.plain)
        .help(option.label)
    }
}

/// Lifts this dropdown above the overlay windows.
///
/// The overlay sits at the shielding level and, while armed, captures mouse
/// input. This panel is a menu-level window, so without this it would be
/// covered by the overlay and every slider in it would be dead — the user could
/// see the controls and not touch them.
///
/// Implemented as a zero-size background view because SwiftUI gives no direct
/// handle on the window hosting a MenuBarExtra's content.
private struct DropdownLevelRaiser: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        raise(view)
        return view
    }

    /// Also applied on update: the dropdown's host window is torn down and
    /// rebuilt each time the menu opens, so setting the level only at creation
    /// would work exactly once.
    func updateNSView(_ nsView: NSView, context: Context) {
        raise(nsView)
    }

    private func raise(_ view: NSView) {
        // Deferred because `view.window` is nil until the view is installed in
        // a window, which has not happened yet inside makeNSView.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            let target = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            if window.level != target { window.level = target }
        }
    }
}
