import AppKit

final class TableRowGeometry: NSObject {
    let rowTops: [CGFloat]
    let sourceOffsets: [Int]

    init(rowTops: [CGFloat], sourceOffsets: [Int]) {
        self.rowTops = rowTops
        self.sourceOffsets = sourceOffsets
    }

    func row(at y: CGFloat) -> Int? {
        guard y >= 0, let bottom = rowTops.last, y <= bottom else { return nil }
        return sourceOffsets.indices.first { rowTops.indices.contains($0 + 1) && y < rowTops[$0 + 1] }
            ?? sourceOffsets.indices.last
    }
}

struct TableViewportAnchor {
    let location: Int
    let visibleY: CGFloat
}

extension NativeTextView {
    func tableCaretRect(at offset: Int) -> CGRect? {
        guard let layout = textLayoutManager,
              let location = layout.textContentManager?.location(layout.documentRange.location, offsetBy: offset) else { return nil }
        var result: CGRect?
        layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: []) { _, rect, _, _ in
            result = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            return false
        }
        return result
    }

    func takeTableViewportAnchor(at location: Int) -> TableViewportAnchor? {
        if let pending = pendingTableViewportAnchor {
            pendingTableViewportAnchor = nil
            return pending
        }
        guard let clip = enclosingScrollView?.contentView,
              let caret = tableCaretRect(at: location) else { return nil }
        let visible = convert(clip.bounds, from: clip)
        guard caret.minY >= visible.minY, caret.minY < visible.maxY else { return nil }
        return TableViewportAnchor(location: location, visibleY: caret.minY - visible.minY)
    }

    func settleTableTransition(anchor: TableViewportAnchor?) {
        guard let scroll = enclosingScrollView else { return }
        pendingFullLayoutMeasure = true
        recalcOverscroll(for: scroll, debugTag: "tableTransition")
        pendingFullLayoutMeasure = false
        guard let anchor, let caret = tableCaretRect(at: anchor.location) else { return }
        let clip = scroll.contentView
        let point = clip.convert(NSPoint(x: 0, y: caret.minY), from: self)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: point.y - anchor.visibleY))
        scroll.reflectScrolledClipView(clip)
        (scroll as? ClampedScrollView)?.clampToInsets()
    }

    func activateRenderedTable(at event: NSEvent) {
        guard isEditable, !configuration.rawSourceMode, event.clickCount == 1,
              event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
              let layout = textLayoutManager else { return }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var hit: (anchor: Int, row: Int)?
        layout.enumerateTextLayoutFragments(from: nil, options: []) { fragment in
            let local = NSPoint(x: containerPoint.x - fragment.layoutFragmentFrame.minX,
                                y: containerPoint.y - fragment.layoutFragmentFrame.minY)
            if let table = fragment as? MarkdownTextLayoutFragment,
               let found = table.renderedTableHit(at: local) {
                hit = found
                return false
            }
            return true
        }
        if let hit { _ = activateTableRow(anchor: hit.anchor, row: hit.row, event: event) }
    }

    @discardableResult
    func activateTableRow(anchor: Int, row: Int, event: NSEvent) -> Bool {
        guard isEditable, !configuration.rawSourceMode, event.clickCount == 1,
              event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
              let storage = textStorage, anchor >= 0, anchor < storage.length,
              let geometry = storage.attribute(.tableRowGeometry, at: anchor, effectiveRange: nil) as? TableRowGeometry,
              geometry.sourceOffsets.indices.contains(row), let clip = enclosingScrollView?.contentView else { return false }
        let location = anchor + geometry.sourceOffsets[row]
        guard location >= 0, location < storage.length else { return false }
        let selection = selectedRange()
        // AppKit must see the original selection to initiate a selected-text drag.
        guard selection.length == 0 || !NSLocationInRange(location, selection) else { return false }
        let click = clip.convert(event.locationInWindow, from: nil)
        pendingTableViewportAnchor = TableViewportAnchor(location: location, visibleY: click.y - clip.bounds.minY)
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: location, length: 0))
        pendingTableViewportAnchor = nil
        return true
    }
}
