import AppKit

extension NativeTextView {
    override func keyDown(with event: NSEvent) {
        // Caret-only actions must not enter text-change bookkeeping.
        if typeThroughClosingDelimiter(for: event) { return }
        super.keyDown(with: event)
    }

    func typeThroughClosingDelimiter(for event: NSEvent) -> Bool {
        guard event.type == .keyDown, let closer = event.characters,
              closer == ")" || closer == "]" || closer == "}",
              event.modifierFlags.intersection([.command, .control]).isEmpty,
              isEditable, !hasMarkedText(), !configuration.rawSourceMode,
              configuration.lists.autoClosePairsEnabled,
              undoManager?.isUndoing != true, undoManager?.isRedoing != true else { return false }
        if let coordinator = delegate as? NativeTextViewCoordinator,
           coordinator.isProgrammaticEdit || coordinator.isWritingToolsActive { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        guard let text = textStorage?.mutableString,
              selection.location >= 0, selection.location < text.length,
              text.substring(with: NSRange(location: selection.location, length: 1)) == closer else { return false }
        let next = NSRange(location: selection.location + 1, length: 0)
        setSelectedRange(next)
        scrollRangeToVisible(next)
        return true
    }
}
