import AppKit
import SwiftUI
import Testing
@testable import MarkdownEngine

@Suite("Table viewport", .serialized)
@MainActor
struct TableViewportTests {
    @Test func renderedRowsRetainWrappedGeometryInCache() throws {
        let source = "| A | B |\n| --- | --- |\n| first | short |\n| second | " + String(repeating: "long wrapped content ", count: 12) + " |\n| third | short |"
        let parsed = try #require(MarkdownStyler.parseTableSource(source))
        let font = NSFont.systemFont(ofSize: 15)
        let ctx = MarkdownStyler.StylingContext(
            nsText: source as NSString, tokens: [], codeTokens: [], activeTokenIndices: [],
            baseFont: font, layoutBridge: nil, baseDefaultLineHeight: 18,
            codeBackgroundColor: .windowBackgroundColor, latexMarkerFont: font,
            configuration: .default, wikiLinkIDProvider: { _ in nil }
        )
        let appearance = try #require(NSAppearance(named: .aqua))
        let rendered = MarkdownStyler.tableImage(for: source, parsed: parsed, ctx: ctx, appearance: appearance, availableWidth: 300)
        let cached = MarkdownStyler.tableImage(for: source, parsed: parsed, ctx: ctx, appearance: appearance, availableWidth: 300)
        #expect(rendered.rowTops.count == 5)
        #expect(rendered.rowTops[3] - rendered.rowTops[2] > rendered.rowTops[2] - rendered.rowTops[1])
        #expect(cached.image === rendered.image)
        #expect(cached.rowTops == rendered.rowTops)
        let geometry = TableRowGeometry(rowTops: rendered.rowTops, sourceOffsets: [0, 24, 44, 80])
        for row in 0..<4 {
            #expect(geometry.row(at: (rendered.rowTops[row] + rendered.rowTops[row + 1]) / 2) == row)
        }
        #expect(geometry.row(at: -1) == nil)
        #expect(geometry.row(at: rendered.image.size.height + 1) == nil)
    }
    @Test func renderedRowActivationPreservesTheClickedPosition() throws {
        try withEditor(sample()) { view in
            let storage = try #require(view.textStorage)
            let anchor = (view.string as NSString).range(of: "| Row").location
            let geometry = try #require(storage.attribute(.tableRowGeometry, at: anchor, effectiveRange: nil) as? TableRowGeometry)
            #expect(geometry.sourceOffsets.count == 81)
            #expect(anchor + geometry.sourceOffsets[1] == (view.string as NSString).range(of: "| 0 | Value").location)
            let scroll = try #require(view.enclosingScrollView)
            for row in [1, 40, 79] {
                view.setSelectedRange(NSRange(location: 0, length: 0))
                view.textLayoutManager?.ensureLayout(for: view.textLayoutManager!.documentRange)
                let geometry = try #require(storage.attribute(.tableRowGeometry, at: anchor, effectiveRange: nil) as? TableRowGeometry)
                let expected = anchor + geometry.sourceOffsets[row]
                let clickY: CGFloat = 140
                let tableTop = try #require(view.tableCaretRect(at: anchor)).minY
                let imageY = (geometry.rowTops[row] + geometry.rowTops[row + 1]) / 2
                scroll.contentView.scroll(to: NSPoint(x: 0, y: tableTop + imageY - clickY))
                let expectedVisibleY = tableTop + imageY - scroll.contentView.bounds.minY
                let point = view.convert(NSPoint(x: 40, y: tableTop + imageY), to: nil)
                let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                view.activateRenderedTable(at: event)
                #expect(view.selectedRange().location == expected)
                let visibleY = try #require(view.tableCaretRect(at: expected)).minY - scroll.contentView.bounds.minY
                if try #require(view.tableCaretRect(at: expected)).minY < expectedVisibleY {
                    #expect(scroll.contentView.bounds.minY == 0)
                } else {
                    #expect(abs(visibleY - expectedVisibleY) < 1)
                }
                #expect(view.string == sample())
            }
        }
    }

    @Test func modifiedClicksRetainNativeSelection() throws {
        try withEditor(sample()) { view in
            let anchor = (view.string as NSString).range(of: "| Row").location
            let prior = view.selectedRange()
            for flags in [NSEvent.ModifierFlags.shift, .command, .option, .control] {
                let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                #expect(!view.activateTableRow(anchor: anchor, row: 10, event: event))
                #expect(view.selectedRange() == prior)
            }
        }
    }

    @Test func selectedRenderedTableRetainsSelectionForNativeDrag() throws {
        try withEditor(sample()) { view in
            let anchor = (view.string as NSString).range(of: "| Row").location
            let geometry = try #require(view.textStorage?.attribute(.tableRowGeometry, at: anchor, effectiveRange: nil) as? TableRowGeometry)
            let range = NSRange(location: 0, length: (view.string as NSString).range(of: "After table.").location)
            view.setSelectedRange(range)
            let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            #expect(geometry.sourceOffsets.count > 40)
            #expect(!view.activateTableRow(anchor: anchor, row: 40, event: event))
            #expect(view.selectedRange() == range)
        }
    }

    @Test func deferredTableRestylePreservesFollowingText() throws {
        try withEditor(sample()) { view in
            let source = view.string as NSString
            view.setSelectedRange(NSRange(location: source.range(of: "Value for row 79").location, length: 0))
            let after = source.range(of: "After table.").location
            let scroll = try #require(view.enclosingScrollView)
            let oldY = try #require(view.tableCaretRect(at: after)).minY
            scroll.contentView.scroll(to: NSPoint(x: 0, y: oldY - 100))
            let coordinator = try #require(view.delegate as? NativeTextViewCoordinator)
            coordinator.activeTokenIndices = []
            coordinator.needsRestyleAfterDrag = true
            view.setSelectedRange(NSRange(location: after, length: 0))
            let newY = try #require(view.tableCaretRect(at: after)).minY - scroll.contentView.bounds.minY
            #expect(abs(newY - 100) < 1)
        }
    }

    private func sample() -> String {
        "Start\n\n| Row | Description |\n| --- | --- |\n"
            + (0..<80).map { "| \($0) | Value for row \($0) |" }.joined(separator: "\n")
            + "\n\nAfter table.\n\n" + String(repeating: "Following text.\n\n", count: 40)
    }

    private func withEditor(_ source: String, body: (NativeTextView) throws -> Void) throws {
        _ = NSApplication.shared
        let stack = HeightBehaviorStack(viewport: NSSize(width: 600, height: 400))
        let view = stack.textView
        view.isEditable = true
        view.isSelectable = true
        view.isVerticallyResizable = true
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.heightTracksTextView = false
        view.textContainer?.widthTracksTextView = true
        let coordinator = NativeTextViewCoordinator(text: .constant(source), fontName: "SF Pro", fontSize: 13,
            isWikiLinkActive: .constant(false), onLinkClick: nil, onInlineSelectionChange: nil)
        let layout = try #require(view.textLayoutManager)
        let layoutDelegate = MarkdownLayoutManagerDelegate()
        layout.delegate = layoutDelegate
        coordinator.layoutDelegate = layoutDelegate
        let bridge = LayoutBridge(layout)
        coordinator.layoutBridge = bridge
        view.layoutBridge = bridge
        coordinator.textView = view
        view.delegate = coordinator
        coordinator.rebuildTextStorageAndStyle(view, from: source)
        view.recalcOverscroll(for: stack.scrollView)
        try body(view)
        view.delegate = nil
    }
}
