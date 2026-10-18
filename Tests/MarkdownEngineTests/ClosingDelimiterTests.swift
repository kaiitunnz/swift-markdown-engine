import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@Suite("Closing delimiter type-through", .serialized)
@MainActor
struct ClosingDelimiterTests {
    @Test(arguments: [("(", ")"), ("[", "]"), ("{", "}")])
    func typedCloserAdvancesOverExistingPair(pair: (String, String)) {
        withEditor("") { view, coordinator in
            view.insertText(pair.0, replacementRange: view.selectedRange())
            view.insertText("text", replacementRange: view.selectedRange())
            let expected = pair.0 + "text" + pair.1
            #expect(view.string == expected)
            view.keyDown(with: key(pair.1))
            #expect(view.string == expected)
            #expect(view.selectedRange() == NSRange(location: expected.utf16.count, length: 0))
            #expect(coordinator.lastComputedStorage == expected)
        }
    }

    @Test func bothWikiClosersAreConsumed() {
        withEditor("") { view, coordinator in
            for text in ["[", "[", "Label"] { view.insertText(text, replacementRange: view.selectedRange()) }
            #expect(view.string == "[[Label]]")
            for _ in 0..<2 { view.keyDown(with: key("]")) }
            #expect(view.string == "[[Label]]")
            #expect(view.selectedRange() == NSRange(location: 9, length: 0))
            #expect(coordinator.lastComputedStorage == "[[Label]]")
        }
    }

    @Test func nestedPairsAndUnicodeKeepCaretPositions() {
        let prefix = "👩🏽‍💻 é "
        withEditor(prefix) { view, coordinator in
            for text in ["(", "{", "[", "content"] { view.insertText(text, replacementRange: view.selectedRange()) }
            let expected = prefix + "({[content]})"
            for closer in ["]", "}", ")"] { view.keyDown(with: key(closer)) }
            #expect(view.string == expected)
            #expect(view.selectedRange() == NSRange(location: expected.utf16.count, length: 0))
            #expect(coordinator.lastComputedStorage == expected)
        }
    }

    @Test func anotherCloserInsertsAfterTypeThrough() {
        withEditor("()") { view, coordinator in
            view.setSelectedRange(NSRange(location: 1, length: 0))
            for _ in 0..<2 { view.keyDown(with: key(")")) }
            #expect(view.string == "())")
            #expect(view.selectedRange() == NSRange(location: 3, length: 0))
            #expect(coordinator.lastComputedStorage == "())")
        }
    }

    @Test func existingPairsWorkAfterCaretMovement() {
        withEditor("(text)") { view, _ in
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.setSelectedRange(NSRange(location: 5, length: 0))
            view.keyDown(with: key(")", modifiers: .option))
            #expect(view.string == "(text)")
            #expect(view.selectedRange() == NSRange(location: 6, length: 0))
        }
    }

    @Test(arguments: [("", ")"), ("}", ")}"), ("x)", ")x)")])
    func unmatchedInputStillInserts(test: (String, String)) {
        withEditor(test.0) { view, coordinator in
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.keyDown(with: key(")"))
            #expect(view.string == test.1)
            #expect(coordinator.lastComputedStorage == test.1)
        }
    }

    @Test func selectedTextIsReplaced() {
        withEditor("text)") { view, coordinator in
            view.setSelectedRange(NSRange(location: 0, length: 4))
            view.keyDown(with: key(")"))
            #expect(view.string == "))")
            #expect(coordinator.lastComputedStorage == "))")
        }
    }

    @Test func programmaticInsertionStaysLiteral() {
        withEditor("()") { view, coordinator in
            view.setSelectedRange(NSRange(location: 1, length: 0))
            view.insertText(")", replacementRange: view.selectedRange())
            #expect(view.string == "())")
            #expect(coordinator.lastComputedStorage == "())")
        }
    }

    @Test func singleCharacterPasteStaysLiteral() {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        }
        defer { pasteboard.clearContents(); if !saved.isEmpty { pasteboard.writeObjects(saved) } }
        pasteboard.clearContents()
        pasteboard.setString(")", forType: .string)
        withEditor("()") { view, coordinator in
            view.setSelectedRange(NSRange(location: 1, length: 0))
            view.paste(nil)
            #expect(view.string == "())")
            #expect(coordinator.lastComputedStorage == "())")
        }
    }

    @Test func noEditOrUndoIsRecordedAndNextEditStaysTrusted() {
        withEditor("(text)") { view, coordinator in
            view.undoManager?.removeAllActions()
            view.setSelectedRange(NSRange(location: 5, length: 0))
            view.keyDown(with: key(")"))
            #expect(!view.undoManager!.canUndo)
            #expect(coordinator.pendingEditCount == 0)
            #expect(coordinator.lastComputedStorage == "(text)")
            view.insertText("!", replacementRange: view.selectedRange())
            #expect(view.string == "(text)!")
            #expect(coordinator.lastComputedStorage == "(text)!")
            #expect(coordinator.debugLastEditWasTrusted == true)
        }
    }

    @Test func undoAfterTypeThroughRestoresTheBodyEdit() {
        withEditor("()") { view, _ in
            view.setSelectedRange(NSRange(location: 1, length: 0))
            let undo = view.undoManager!
            undo.removeAllActions()
            undo.groupsByEvent = false
            undo.beginUndoGrouping()
            view.insertText("body", replacementRange: view.selectedRange())
            undo.endUndoGrouping()
            view.breakUndoCoalescing()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            view.keyDown(with: key(")"))
            undo.undo()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            #expect(view.string == "()")
            undo.redo()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            #expect(view.string == "(body)")
        }
    }

    @Test(arguments: ["disabled", "raw"])
    func configurationRetainsLiteralInsertion(setting: String) {
        withEditor("()") { view, coordinator in
            view.configuration.lists.autoClosePairsEnabled = setting != "disabled"
            coordinator.configuration.lists = view.configuration.lists
            view.configuration.rawSourceMode = setting == "raw"
            coordinator.configuration.rawSourceMode = view.configuration.rawSourceMode
            view.setSelectedRange(NSRange(location: 1, length: 0))
            view.keyDown(with: key(")"))
            #expect(view.string == "())")
        }
    }

    @Test func markedTextAndProtectedOperationsAreNotConsumed() {
        withEditor("()") { view, coordinator in
            view.setSelectedRange(NSRange(location: 1, length: 0))
            for modifiers: NSEvent.ModifierFlags in [.command, .control] {
                #expect(!view.typeThroughClosingDelimiter(for: key(")", modifiers: modifiers)))
            }
            coordinator.isProgrammaticEdit = true
            #expect(!view.typeThroughClosingDelimiter(for: key(")")))
            coordinator.isProgrammaticEdit = false
            coordinator.isWritingToolsActive = true
            #expect(!view.typeThroughClosingDelimiter(for: key(")")))
            coordinator.isWritingToolsActive = false
            view.isEditable = false
            #expect(!view.typeThroughClosingDelimiter(for: key(")")))
            view.isEditable = true
            #expect(view.string == "()")
            view.setMarkedText("compose", selectedRange: NSRange(location: 7, length: 0), replacementRange: view.selectedRange())
            #expect(view.hasMarkedText())
            let before = view.string
            let selection = view.selectedRange()
            #expect(!view.typeThroughClosingDelimiter(for: key(")")))
            #expect(view.string == before)
            #expect(view.selectedRange() == selection)
        }
    }

    @Test func quotesRemainOutsidePairCompletion() {
        withEditor("\"'") { view, _ in
            for (index, quote) in ["\"", "'"].enumerated() {
                view.setSelectedRange(NSRange(location: index, length: 0))
                #expect(!view.typeThroughClosingDelimiter(for: key(quote)))
            }
            #expect(view.string == "\"'")
        }
    }

    @Test func codePairingKeepsTheSameTypeThroughBehavior() {
        let source = "```swift\ncall()\n```"
        withEditor(source) { view, coordinator in
            let close = (source as NSString).range(of: ")").location
            view.setSelectedRange(NSRange(location: close, length: 0))
            view.keyDown(with: key(")"))
            #expect(view.string == source)
            #expect(view.selectedRange() == NSRange(location: close + 1, length: 0))
            #expect(coordinator.lastComputedStorage == source)
        }
    }

    private func key(_ character: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        let shifted = character == ")" || character == "}"
        return NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: shifted ? modifiers.union(.shift) : modifiers,
            timestamp: 0, windowNumber: 0, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: false,
            keyCode: character == ")" ? 29 : 30)!
    }

    private func withEditor(_ source: String, body: (NativeTextView, NativeTextViewCoordinator) -> Void) {
        _ = NSApplication.shared
        let view = NativeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.isEditable = true
        view.isSelectable = true
        view.allowsUndo = true
        view.configuration = .default
        let coordinator = NativeTextViewCoordinator(text: .constant(source), fontName: "SF Pro", fontSize: 14,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        coordinator.textView = view
        view.delegate = coordinator
        coordinator.rebuildTextStorageAndStyle(view, from: source)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        defer { window.contentView = nil; window.close() }
        body(view, coordinator)
    }
}
