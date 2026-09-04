import AppKit
import CoreGraphics

// MARK: - GlobalKeyboardMonitor

/// Listens for system-wide keyboard events (any app) and calls an activity callback.
///
/// Uses a **listen-only** CGEventTap so keystrokes are never intercepted, delayed,
/// or cancelled. The tap fires after the event has already been delivered to the
/// target application.
///
/// Requires Accessibility permission (`AXIsProcessTrusted()`).  When permission is
/// not granted the monitor silently does nothing — the caller keeps working via
/// Touch Bar interaction as before.
@MainActor
final class GlobalKeyboardMonitor {

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called on @MainActor whenever a key-down event is detected.
    private let onActivity: @MainActor () -> Void

    // MARK: - Init

    init(onActivity: @MainActor @escaping () -> Void) {
        self.onActivity = onActivity
    }

    // MARK: - Lifecycle

    /// Starts the keyboard monitor.
    /// If Accessibility permission is not yet granted, shows the system prompt and
    /// returns without installing the tap (no crash, no assertion).
    func start() {
        guard eventTap == nil else { return }

        // Prompt for Accessibility permission if needed (shows system dialog once).
        guard AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        ) else {
            // Permission denied — fallback to Touch Bar interaction only.
            return
        }

        installTap()
    }

    /// Stops and removes the keyboard monitor.
    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    // MARK: - Private

    private func installTap() {
        // Capture self weakly via an unmanaged pointer so the C callback can reach us.
        let selfPtr = Unmanaged.passRetained(self)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,    // After event is delivered — truly passive
            options: .listenOnly,           // Never intercepts, never blocks
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<GlobalKeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                // Dispatch back to @MainActor so onActivity runs on the main thread.
                Task { @MainActor in
                    monitor.onActivity()
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr.toOpaque()
        )

        guard let tap else {
            // Tap creation failed (e.g. permission revoked mid-session).
            selfPtr.release()
            return
        }

        eventTap = tap

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

}
