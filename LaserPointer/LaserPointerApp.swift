//
//  LaserPointerApp.swift
//  LaserPointer
//
//  A menu-bar-only app: no Dock icon, no main window. That requires
//  LSUIElement = YES in Info.plist.
//
//  macOS 13+ is the floor because MenuBarExtra ships in Ventura.
//

import SwiftUI
import AppKit

@main
struct LaserPointerApp: App {

    // @StateObject, not @State: the menu content view is torn down every time
    // the dropdown closes, and the controller owns the overlay windows and the
    // sampling timer. Losing it on close would drop the overlay mid-presentation.
    @StateObject private var controller = PointerController()

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(controller: controller)
                .onAppear { delegate.controller = controller }
        } label: {
            // Filled while armed, outline while idle — the icon is the only
            // status indicator this app has.
            Image(systemName: controller.isEnabled
                  ? "cursorarrow.rays"
                  : "cursorarrow")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Exists for two things SwiftUI cannot do on its own: registering the global
/// hotkey, and guaranteeing overlay teardown at quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    var controller: PointerController?
    private let hotKey = ToggleHotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ToggleHotKey.onToggle = { [weak self] in
            self?.controller?.toggle()
        }
        hotKey.register()
    }

    /// THE teardown path.
    ///
    /// This cannot live in `PointerController.deinit`: the controller is retained
    /// by a @StateObject for the app's lifetime, and `NSApp.terminate` tears the
    /// process down without unwinding SwiftUI state, so that deinit never runs.
    ///
    /// (On a crash or force-quit macOS destroys our windows along with the
    /// process, so there is no way to strand a shielding-level overlay on screen.)
    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        controller?.shutdown()
    }
}
