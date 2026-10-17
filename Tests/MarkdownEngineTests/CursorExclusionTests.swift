import AppKit
import Testing
@testable import MarkdownEngine

@Suite("Cursor exclusions", .serialized)
@MainActor
struct CursorExclusionTests {
    @Test(arguments: [NSEvent.EventType.mouseMoved, .mouseEntered, .cursorUpdate])
    func editableOverlayRetainsArrow(type: NSEvent.EventType) throws {
        try withView { view in
            view.isEditable = true
            view.isCursorExcluded = { _ in true }
            NSCursor.iBeam.set()
            deliver(try event(type), to: view)
            #expect(NSCursor.current.isEqual(NSCursor.arrow))
        }
    }

    @Test(arguments: [NSEvent.EventType.mouseMoved, .mouseEntered, .cursorUpdate])
    func readOnlyOverlayOwnsItsCursor(type: NSEvent.EventType) throws {
        try withView { view in
            view.isEditable = false
            view.isCursorExcluded = { _ in true }
            NSCursor.crosshair.set()
            deliver(try event(type), to: view)
            #expect(NSCursor.current.isEqual(NSCursor.crosshair))
        }
    }

    @Test func editableTextRetainsNativeCursor() throws {
        try withView { view in
            view.isEditable = true
            view.isCursorExcluded = { _ in false }
            NSCursor.arrow.set()
            view.cursorUpdate(with: try event(.cursorUpdate))
            #expect(NSCursor.current.isEqual(NSCursor.iBeam))
        }
    }

    private func withView(_ body: (NativeTextView) throws -> Void) rethrows {
        _ = NSApplication.shared
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isSelectable = true
        defer { NSCursor.arrow.set() }
        try body(view)
    }

    private func event(_ type: NSEvent.EventType) throws -> NSEvent {
        if type == .mouseMoved {
            return try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        }
        return try #require(NSEvent.enterExitEvent(with: type, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }

    private func deliver(_ event: NSEvent, to view: NativeTextView) {
        switch event.type {
        case .mouseMoved: view.mouseMoved(with: event)
        case .mouseEntered: view.mouseEntered(with: event)
        case .cursorUpdate: view.cursorUpdate(with: event)
        default: Issue.record("Unexpected cursor event")
        }
    }
}
