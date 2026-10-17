import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@Suite("List editing", .serialized)
@MainActor
struct ListEditingTests {
    @Test func tabStartsNestedNumberingAndClosesParentGap() {
        let (view, coordinator) = makeEditor("1. Alpha\n2. Beta\n3. Gamma")
        let caret = (view.string as NSString).range(of: "Beta").location + 2
        view.setSelectedRange(NSRange(location: caret, length: 0))
        view.insertText("\t", replacementRange: view.selectedRange())
        #expect(view.string == "1. Alpha\n\t1. Beta\n2. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test func tabContinuesExistingNestedNumbering() {
        let (view, coordinator) = makeEditor("1. Alpha\n\t1. Child\n2. Beta\n3. Gamma")
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "Beta").location, length: 0))
        view.insertText("\t", replacementRange: view.selectedRange())
        #expect(view.string == "1. Alpha\n\t1. Child\n\t2. Beta\n2. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test func backtabContinuesParentNumbering() {
        let (view, coordinator) = makeEditor("1. Alpha\n\t1. Child\n\t2. Beta\n2. Gamma")
        view.setSelectedRange(NSRange(location: (view.string as NSString).range(of: "Beta").location, length: 0))
        #expect(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(view.string == "1. Alpha\n\t1. Child\n2. Beta\n3. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    struct IndentCase: Sendable {
        let source: String
        let target: String
        let expected: String
        var backward = false
    }

    @Test(arguments: [
        IndentCase(source: "5. Alpha\n6. Beta\n7. Gamma", target: "Beta", expected: "5. Alpha\n\t1. Beta\n6. Gamma"),
        IndentCase(source: "- Parent\n\t7. Existing\n8. Beta", target: "Beta", expected: "- Parent\n\t7. Existing\n\t8. Beta"),
        IndentCase(source: "1. Parent\n\t1. Child\n\t\t1. Deep\n2. Beta", target: "Beta", expected: "1. Parent\n\t1. Child\n\t\t1. Deep\n\t2. Beta"),
        IndentCase(source: "1. First\n\t8. Older\n2. Parent\n3. Beta", target: "Beta", expected: "1. First\n\t8. Older\n2. Parent\n\t1. Beta"),
        IndentCase(source: "1. First\n2. Beta\n3. Last\n# Separate\n8. Other\n9. Tail", target: "Beta", expected: "1. First\n\t1. Beta\n2. Last\n# Separate\n8. Other\n9. Tail"),
        IndentCase(source: "1. First\n2. Beta\n3. Last\n\nProse\n\n8. Other\n9. Tail", target: "Beta", expected: "1. First\n\t1. Beta\n2. Last\n\nProse\n\n8. Other\n9. Tail"),
        IndentCase(source: "1) First\n2) Beta\n3) Last", target: "Beta", expected: "1) First\n\t1) Beta\n2) Last"),
        IndentCase(source: "- [x] First\n- [ ] Beta\n+ Last", target: "Beta", expected: "- [x] First\n\t- [ ] Beta\n+ Last"),
        IndentCase(source: "* First\n* Beta", target: "Beta", expected: "* First\n\t* Beta"),
        IndentCase(source: "1. First\n    1. Child\n2. Beta\n3. Last", target: "Beta", expected: "1. First\n    1. Child\n\t2. Beta\n2. Last"),
        IndentCase(source: "1. First\n    1. Beta\n2. Last", target: "Beta", expected: "1. First\n2. Beta\n3. Last", backward: true),
        IndentCase(source: "1. First\n  1. Beta\n2. Last", target: "Beta", expected: "1. First\n2. Beta\n3. Last", backward: true),
        IndentCase(source: "1. First\r\n2. Beta\r\n3. Last\r\n", target: "Beta", expected: "1. First\r\n\t1. Beta\r\n2. Last\r\n"),
        IndentCase(source: "9. First\n10. 👩🏽‍💻 Beta é\n11. Last", target: "👩🏽‍💻 Beta é", expected: "9. First\n\t1. 👩🏽‍💻 Beta é\n10. Last"),
        IndentCase(source: "1. First\n2. Beta\n\n3. Last", target: "Beta", expected: "1. First\n\t1. Beta\n\n2. Last"),
        IndentCase(source: "1. First\n2. Beta\n\t1. Child\n3. Last", target: "Beta", expected: "1. First\n\t1. Beta\n\t2. Child\n2. Last")
    ])
    func indentationMatchesReferenceWorkflow(test: IndentCase) throws {
        let range = (test.source as NSString).range(of: test.target)
        let plan = try #require(ListEditPlan.indent(test.source, selection: NSRange(location: NSMaxRange(range), length: 0),
                                                   backward: test.backward, maximumDepth: 10, codeRanges: []))
        #expect(plan.result == test.expected)
        #expect(plan.selection.location == NSMaxRange((test.expected as NSString).range(of: test.target)))
    }

    @Test func selectedItemsKeepSelectionAndExcludeTrailingLine() throws {
        let source = "1. First\n2. Beta\n3. Gamma\n4. Last"
        let start = (source as NSString).range(of: "2. Beta").location
        let end = (source as NSString).range(of: "4. Last").location
        let plan = try #require(ListEditPlan.indent(source, selection: NSRange(location: start, length: end - start),
                                                   backward: false, maximumDepth: 10, codeRanges: []))
        #expect(plan.result == "1. First\n\t1. Beta\n\t2. Gamma\n2. Last")
        #expect((plan.result as NSString).substring(with: plan.selection) == "1. Beta\n\t2. Gamma\n")
    }

    @Test func codeAndConfigurationGuards() throws {
        let source = "1. First\n\t1. Beta"
        let range = NSRange(location: (source as NSString).length, length: 0)
        #expect(ListEditPlan.indent(source, selection: range, backward: false, maximumDepth: 1, codeRanges: [])?.result == source)
        #expect(ListEditPlan.indent("1. Beta", selection: NSRange(location: 7, length: 0), backward: true, maximumDepth: 3, codeRanges: [])?.result == "1. Beta")
        #expect(ListEditPlan.indent("2. Beta", selection: NSRange(location: 7, length: 0), backward: false, maximumDepth: 3, codeRanges: [NSRange(location: 0, length: 7)]) == nil)
        for raw in [false, true] {
            let (view, coordinator) = makeEditor("1. Alpha\n2. Beta")
            view.configuration.lists.helpersEnabled = false
            coordinator.configuration.lists.helpersEnabled = false
            view.configuration.rawSourceMode = raw
            coordinator.configuration.rawSourceMode = raw
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            view.insertText("\t", replacementRange: view.selectedRange())
            #expect(view.string == "1. Alpha\n2. Beta\t")
        }
    }

    @Test func enterRenumbersFollowingItemsAndKeepsDelimiter() {
        for delimiter in [".", ")"] {
            let source = "1\(delimiter) Alpha\n2\(delimiter) Beta"
            let (view, coordinator) = makeEditor(source)
            let point = (source as NSString).range(of: "Alpha").location + 5
            view.setSelectedRange(NSRange(location: point, length: 0))
            view.insertText("\n", replacementRange: view.selectedRange())
            #expect(view.string == "1\(delimiter) Alpha\n2\(delimiter) \n3\(delimiter) Beta")
            #expect(coordinator.lastComputedStorage == view.string)
        }
    }

    @Test(arguments: ["\n", "\r\n"])
    func emptyItemExitClosesGap(newline: String) {
        let source = "1. Alpha" + newline + "2. " + newline + "3. Beta"
        let (view, coordinator) = makeEditor(source)
        let point = NSMaxRange((source as NSString).range(of: "2. "))
        view.setSelectedRange(NSRange(location: point, length: 0))
        view.insertText("\n", replacementRange: view.selectedRange())
        #expect(view.string == "1. Alpha" + newline + newline + "2. Beta")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test func structuralEditUndoRedoRestoresStorageAndSelection() throws {
        let source = "1. Alpha\n2. 👩🏽‍💻 Beta\n3. Gamma"
        let (view, coordinator) = makeEditor(source)
        let selection = NSRange(location: NSMaxRange((source as NSString).range(of: "Beta")), length: 0)
        view.setSelectedRange(selection)
        let undo = try #require(view.undoManager)
        undo.groupsByEvent = false
        undo.removeAllActions()
        undo.beginUndoGrouping()
        view.insertText("\t", replacementRange: selection)
        undo.endUndoGrouping()
        #expect(view.string == "1. Alpha\n\t1. 👩🏽‍💻 Beta\n2. Gamma")
        undo.undo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        #expect(view.string == source)
        #expect(coordinator.lastComputedStorage == source, "Storage after undo: \(coordinator.lastComputedStorage)")
        #expect(view.selectedRange() == selection, "Selection after undo: \(view.selectedRange()) vs \(selection)")
        undo.redo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        #expect(view.string == "1. Alpha\n\t1. 👩🏽‍💻 Beta\n2. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test(arguments: ["tab", "backtab", "enter"])
    func structuralEditsPreserveOpaqueLinkAndImageMetadata(command: String) throws {
        let prefix = command == "backtab" ? "\t1. " : "2. "
        let source = "1. Alpha\n" + prefix + "Beta [[Name|opaque]] ![[Picture|image|240]]\n3. Gamma [[Other|other]]"
        let (view, coordinator) = makeEditor(source)
        let point = NSMaxRange((view.string as NSString).range(of: "Beta"))
        view.setSelectedRange(NSRange(location: point, length: 0))
        let undo = try #require(view.undoManager)
        undo.groupsByEvent = false
        undo.removeAllActions()
        undo.beginUndoGrouping()
        let expected: String
        switch command {
        case "tab":
            view.insertText("\t", replacementRange: view.selectedRange())
            expected = "1. Alpha\n\t1. Beta [[Name|opaque]] ![[Picture|image|240]]\n2. Gamma [[Other|other]]"
        case "backtab":
            _ = coordinator.textView(view, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
            expected = "1. Alpha\n2. Beta [[Name|opaque]] ![[Picture|image|240]]\n3. Gamma [[Other|other]]"
        default:
            view.insertText("\n", replacementRange: view.selectedRange())
            expected = "1. Alpha\n2. Beta\n3.  [[Name|opaque]] ![[Picture|image|240]]\n4. Gamma [[Other|other]]"
        }
        undo.endUndoGrouping()
        #expect(coordinator.lastComputedStorage == expected)
        undo.undo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        #expect(coordinator.lastComputedStorage == source)
        undo.redo()
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        #expect(coordinator.lastComputedStorage == expected)
    }

    @Test func fencedListTextIsNeverRenumbered() {
        let source = "1. Alpha\n2. Beta\n\n    ```\n    8. Code\n    ```\n3. Gamma"
        let (view, coordinator) = makeEditor(source)
        view.setSelectedRange(NSRange(location: NSMaxRange((source as NSString).range(of: "Beta")), length: 0))
        view.insertText("\t", replacementRange: view.selectedRange())
        #expect(view.string == "1. Alpha\n\t1. Beta\n\n    ```\n    8. Code\n    ```\n2. Gamma", "Actual fenced result: \(view.string)")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test func nativeCommandsHonorConfiguredDepthBeyondThree() {
        let source = "1. Root\n\t\t\t1. Deep"
        let (view, coordinator) = makeEditor(source)
        view.configuration.lists.maximumNestingLevel = 6
        coordinator.configuration.lists.maximumNestingLevel = 6
        view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        view.insertText("\t", replacementRange: view.selectedRange())
        #expect(view.string == "1. Root\n\t\t\t\t1. Deep")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test func selectedItemsOutdentTogether() throws {
        let source = "1. Root\n\t1. Beta\n\t2. Gamma\n2. Last"
        let start = (source as NSString).range(of: "Beta").location
        let end = NSMaxRange((source as NSString).range(of: "Gamma"))
        let plan = try #require(ListEditPlan.indent(source, selection: NSRange(location: start, length: end - start),
                                                   backward: true, maximumDepth: 6, codeRanges: []))
        #expect(plan.result == "1. Root\n2. Beta\n3. Gamma\n4. Last")
        #expect((plan.result as NSString).substring(with: plan.selection) == "Beta\n3. Gamma")
    }

    @Test(arguments: ["    ```", "~~~"])
    func unparsedFencesStillSuppressListHelpers(fence: String) {
        for insertion in ["\t", "\n"] {
            let source = fence + "\n    8. Code\n" + fence
            let (view, coordinator) = makeEditor(source)
            let point = NSMaxRange((source as NSString).range(of: "Code"))
            view.setSelectedRange(NSRange(location: point, length: 0))
            view.insertText(insertion, replacementRange: view.selectedRange())
            #expect(view.string == (source as NSString).replacingCharacters(in: NSRange(location: point, length: 0), with: insertion))
            #expect(coordinator.lastComputedStorage == view.string)
        }
    }

    @Test(arguments: [" ```code```", "  ```language`text", "    ```\n    8. Code", "    ~~~\n    8. Code",
                      "- Parent\n  ```\n  8. Code", "- Parent\n   ~~~\n  8. Code",
                      "1. Parent\n   ```\n   8. Code\n\nAfter code", "        ```\n    8. Code",
                      "  ```\n8. Code\n ```", "- Parent\n   ```\n  8. Code\n  ```"])
    func codeParagraphsDoNotDisableFollowingLists(paragraph: String) {
        let source = paragraph + "\n\n1. Alpha\n2. Beta\n3. Gamma"
        let (view, coordinator) = makeEditor(source)
        view.setSelectedRange(NSRange(location: NSMaxRange((view.string as NSString).range(of: "Beta")), length: 0))
        view.insertText("\t", replacementRange: view.selectedRange())
        #expect(view.string == paragraph + "\n\n1. Alpha\n\t1. Beta\n2. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
        _ = coordinator.textView(view, doCommandBy: #selector(NSResponder.insertBacktab(_:)))
        #expect(view.string == source)
        view.insertText("\n", replacementRange: view.selectedRange())
        #expect(view.string == paragraph + "\n\n1. Alpha\n2. Beta\n3. \n4. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
    }

    @Test(arguments: [" ```\n8. Code", "  ~~~\n8. Code", "   ```\n8. Code", "- Parent\n   ```\n  8. Code", "    ```\n    8. Code\n    ```\n    9. Other",
                      "- Parent\n  ```\n      ```\n  8. Code", " ```\n    ```\n8. Code"])
    func openFencesKeepTheirCodeProtected(source: String) {
        for insertion in ["\t", "\n"] {
            let (view, _) = makeEditor(source)
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            view.insertText(insertion, replacementRange: view.selectedRange())
            #expect(view.string == source + insertion)
        }
    }

    @Test func consecutiveStructuralKeysHaveSeparateUndoActions() throws {
        let source = "1. Alpha\n2. Beta\n3. Gamma"
        let (view, coordinator) = makeEditor(source)
        view.setSelectedRange(NSRange(location: NSMaxRange((source as NSString).range(of: "Beta")), length: 0))
        let undo = try #require(view.undoManager)
        undo.groupsByEvent = false
        undo.removeAllActions()
        for _ in 0..<2 {
            undo.beginUndoGrouping()
            view.insertText("\t", replacementRange: view.selectedRange())
            undo.endUndoGrouping()
        }
        #expect(view.string == "1. Alpha\n\t\t1. Beta\n2. Gamma")
        undo.undo()
        #expect(view.string == "1. Alpha\n\t1. Beta\n2. Gamma")
        #expect(coordinator.lastComputedStorage == view.string)
        undo.undo()
        #expect(view.string == source)
        #expect(coordinator.lastComputedStorage == source)
    }

    private func makeEditor(_ source: String) -> (NativeTextView, NativeTextViewCoordinator) {
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
        return (view, coordinator)
    }
}
