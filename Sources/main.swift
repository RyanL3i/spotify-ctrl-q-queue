import AppKit
import ApplicationServices
import Foundation

final class SpotifyQueueHotkeyApp: NSObject, NSApplicationDelegate {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("Starting Spotify Queue Hotkey...")
        promptForPermissions()
        installEventTap()
    }

    func promptForPermissions() {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            print("Accessibility permission NOT granted.")
            print("Go to System Settings > Privacy & Security > Accessibility")
            print("Enable SpotifyQueue, then quit and reopen the app.")
        } else {
            print("Accessibility permission granted.")
        }

        print("Also make sure Input Monitoring is enabled for SpotifyQueue.")
    }

    func isSpotifyFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.localizedName == "Spotify"
    }

    func quartzMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    func rightClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )

        let up = CGEvent(
            mouseEventSource: source,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        )

        down?.flags = []
        up?.flags = []

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func postKey(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: true
        )

        let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: false
        )

        down?.flags = []
        up?.flags = []

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    func selectAddToQueueByKeyboard() {
        usleep(250_000)

        let downCount = 4
        print("Using downCount = \(downCount)")

        for _ in 0..<downCount {
            postKey(keyCode: 125) // down arrow
            usleep(45_000)
        }

        postKey(keyCode: 36) // return
    }

    func queueHoveredSong() {
        let point = quartzMouseLocation()
        print("Clicking at quartz point: \(point)")

        rightClick(at: point)
        selectAddToQueueByKeyboard()
    }

    func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isControlPressed = flags.contains(.maskControl)
        let isQ = keycode == 12

        guard isControlPressed && isQ else {
            return Unmanaged.passRetained(event)
        }

        print("Detected Ctrl+Q")

        guard isSpotifyFrontmost() else {
            print("Spotify not active")
            return Unmanaged.passRetained(event)
        }

        queueHoveredSong()
        return nil
    }

    func installEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passRetained(event)
            }

            let app = Unmanaged<SpotifyQueueHotkeyApp>
                .fromOpaque(refcon)
                .takeUnretainedValue()

            return app.handleKeyEvent(proxy: proxy, type: type, event: event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            print("Failed to create event tap.")
            print("This usually means Input Monitoring permission is still not active for SpotifyQueue.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            print("Failed to create run loop source for event tap.")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Installed Quartz event tap.")
        print("Hotkey: Ctrl+Q")
    }
}

let application = NSApplication.shared
let delegate = SpotifyQueueHotkeyApp()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()