//
//  ToggleHotKey.swift
//  LaserPointer
//
//  A system-wide hotkey that turns the pointer on and off: ⌃⌥⌘L.
//
//  ============================================================================
//  WHY CARBON, IN 2026
//  ============================================================================
//  This uses the ancient Carbon `RegisterEventHotKey` API on purpose, for a
//  privacy reason rather than a technical one. The modern-looking alternatives
//  both require a TCC permission:
//
//    * NSEvent.addGlobalMonitorForEvents  -> requires Accessibility
//    * CGEventTap                         -> requires Input Monitoring
//
//  Either would mean this app starts asking for the ability to observe every
//  keystroke on the system, and would put it in the same permission bucket as a
//  keylogger. `RegisterEventHotKey` is not TCC-gated: it registers ONE chord
//  with the window server and only ever reports that chord. It is the right
//  tool because it is the least capable one that does the job.
//
//  See also CursorTracker.swift, which avoids the same permission for the mouse
//  by sampling instead of monitoring. Between the two, this app needs no
//  permissions at all. Keep it that way.
//

import AppKit
import Carbon.HIToolbox
import os

@MainActor
final class ToggleHotKey {

    private static let log = Logger(subsystem: "local.LaserPointer", category: "hotkey")

    /// Invoked on ⌃⌥⌘L. Set by the app delegate.
    ///
    /// Static because the Carbon handler is a bare C function pointer and
    /// therefore cannot capture any context.
    static var onToggle: (() -> Void)?

    static let displayName = "⌃⌥⌘L"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers the chord. Failure is logged and otherwise ignored: another app
    /// already owning ⌃⌥⌘L is not worth refusing to launch over, and the menu
    /// bar remains a complete way to drive the app.
    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    ToggleHotKey.onToggle?()
                }
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4C415352), id: 1)   // 'LASR'
        let modifiers = UInt32(controlKey | optionKey | cmdKey)

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            modifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            Self.log.info("toggle hotkey registered: control-option-command-L")
        } else {
            Self.log.error("toggle hotkey registration failed (\(status)) — the menu bar still works")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
