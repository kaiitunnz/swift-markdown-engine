import AppKit

struct ListEditPlan {
    struct Edit {
        let range: NSRange
        let text: String
    }

    let stages: [[Edit]]
    let selection: NSRange
    let source: String
    let result: String

    static func indent(_ source: String, selection: NSRange, backward: Bool,
                       maximumDepth: Int, codeRanges: [NSRange]) -> ListEditPlan? {
        let original = lines(source, codeRanges: codeRanges)
        guard selection.location != NSNotFound, NSMaxRange(selection) <= (source as NSString).length else { return nil }
        let last = selection.length == 0 ? selection.location : NSMaxRange(selection) - 1
        guard let firstLine = original.lastIndex(where: { $0.range.location <= selection.location }),
              let lastLine = original.lastIndex(where: { $0.range.location <= last }) else { return nil }
        let selected = firstLine...lastLine
        guard selected.contains(where: { original[$0].prefix != nil }) else { return nil }
        if !backward, selected.contains(where: { original[$0].columns / 4 >= maximumDepth }) {
            return ListEditPlan(stages: [], selection: selection, source: source, result: source)
        }

        var edits: [Edit] = []
        for index in selected {
            let line = original[index]
            let whitespace = line.whitespace
            let replacement: String
            if backward {
                let minimum = line.prefix?.bullet == "•" ? 4 : 0
                let columns = max(minimum, line.columns - 4)
                if columns >= line.columns { continue }
                replacement = whitespace.contains("\t")
                    ? String(repeating: "\t", count: columns / 4) + String(repeating: " ", count: columns % 4)
                    : String(repeating: " ", count: columns)
            } else {
                replacement = "\t" + whitespace
            }
            edits.append(Edit(range: NSRange(location: line.range.location, length: whitespace.utf16.count), text: replacement))
        }
        return replacing(source, edits: edits, selection: selection, codeRanges: codeRanges)
    }

    static func replacing(_ source: String, edits: [Edit], selection: NSRange,
                          codeRanges: [NSRange], selectionAfterEdit: NSRange? = nil) -> ListEditPlan {
        let oldLines = lines(source, codeRanges: codeRanges)
        let intermediate = applying(edits, to: source)
        var newLines = lines(intermediate, codeRanges: [])
        let nextID = oldLines.count
        let survivingStarts = Dictionary(oldLines.compactMap { line -> (Int, Line)? in
            let anchor = line.range.location + line.whitespace.utf16.count
            if edits.contains(where: { $0.range.length > 0 && NSLocationInRange(anchor, $0.range) }) { return nil }
            return (map(anchor, through: edits), line)
        }, uniquingKeysWith: { first, _ in first })
        for index in newLines.indices {
            let anchor = newLines[index].range.location + newLines[index].whitespace.utf16.count
            if let old = survivingStarts[anchor] {
                newLines[index].id = old.id
                newLines[index].isCode = newLines[index].isCode || old.isCode
            } else {
                newLines[index].id = nextID + index
            }
            if newLines[index].isCode { newLines[index].prefix = nil }
        }

        let oldGroups = groups(oldLines)
        let newGroups = groups(newLines)
        let oldByLine = Dictionary(oldGroups.flatMap { group in group.members.map { ($0.id, group) } }, uniquingKeysWith: { first, _ in first })
        var numbers: [Edit] = []
        for group in newGroups {
            guard let first = group.members.first else { continue }
            let prior = oldByLine[first.id]
            if let prior, prior.members.map(\.id) == group.members.map(\.id), prior.container == group.container {
                continue
            }
            let sameContainer = prior?.container == group.container
            var number = sameContainer ? (prior?.members.first?.prefix?.number ?? 1) : 1
            for line in group.members {
                guard let marker = line.prefix, let current = marker.number else { continue }
                if current != number {
                    numbers.append(Edit(range: NSRange(location: line.range.location + line.whitespace.utf16.count,
                                                       length: marker.digits.utf16.count), text: String(number)))
                }
                number += 1
            }
        }
        numbers.sort { $0.range.location < $1.range.location }
        let mapped = selectionAfterEdit ?? map(selection, through: edits)
        return ListEditPlan(stages: [edits, numbers], selection: map(mapped, through: numbers),
                            source: source, result: applying(numbers, to: intermediate))
    }

    static func isCode(at location: Int, in source: String, codeRanges: [NSRange] = []) -> Bool {
        let text = source as NSString
        guard location <= text.length else { return false }
        let range = text.lineRange(for: NSRange(location: location, length: 0))
        let current = text.substring(with: range)
        guard marker.firstMatch(in: current, range: NSRange(location: 0, length: current.utf16.count)) != nil else { return false }
        return lines(source, codeRanges: codeRanges).last(where: { $0.range.location <= location })?.isCode == true
    }

    func apply(to textView: NSTextView) {
        guard source != result, textView.string == source, let storage = textView.textStorage else { return }
        let before = source as NSString
        let after = result as NSString
        var start = 0
        while start < min(before.length, after.length), before.character(at: start) == after.character(at: start) { start += 1 }
        var suffix = 0
        while suffix < min(before.length - start, after.length - start),
              before.character(at: before.length - suffix - 1) == after.character(at: after.length - suffix - 1) { suffix += 1 }
        let range = NSRange(location: start, length: before.length - start - suffix)
        let replacementRange = NSRange(location: start, length: after.length - start - suffix)
        let attributed = NSMutableAttributedString(attributedString: storage)
        for edits in stages {
            for edit in edits.reversed() { attributed.replaceCharacters(in: edit.range, with: edit.text) }
        }
        let replacement = attributed.attributedSubstring(from: replacementRange)
        Self.replace(in: textView, range: range, with: replacement, selection: selection)
    }

    private static func replace(in textView: NSTextView, range: NSRange, with replacement: NSAttributedString,
                                selection: NSRange) {
        guard textView.isEditable, let storage = textView.textStorage else { return }
        let original = storage.attributedSubstring(from: range)
        let oldSelection = textView.selectedRange()
        let coordinator = textView.delegate as? NativeTextViewCoordinator
        let wasProgrammatic = coordinator?.isProgrammaticEdit ?? false
        coordinator?.isProgrammaticEdit = true
        coordinator?.pendingEditCount = 0
        defer { coordinator?.isProgrammaticEdit = wasProgrammatic }
        let undo = textView.allowsUndo ? textView.undoManager : nil
        textView.breakUndoCoalescing()
        // Native text undo alone misses the structural selection and storage-sync cycle.
        undo?.disableUndoRegistration()
        guard textView.shouldChangeText(in: range, replacementString: replacement.string) else {
            undo?.enableUndoRegistration()
            return
        }
        storage.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(selection)
        undo?.enableUndoRegistration()
        undo?.registerUndo(withTarget: textView) { view in
            replace(in: view, range: NSRange(location: range.location, length: replacement.length),
                    with: original, selection: oldSelection)
        }
        textView.breakUndoCoalescing()
    }

    private struct Prefix {
        let number: Int?
        let digits: String
        let delimiter: String
        let bullet: String
    }

    private struct Line {
        var id: Int
        let range: NSRange
        let text: String
        let whitespace: String
        let columns: Int
        var prefix: Prefix?
        var isCode: Bool
    }

    private struct Container: Hashable {
        let boundary: Int
        let parent: Int?
        let columns: Int
    }

    private struct Group {
        let container: Container
        let delimiter: String
        var members: [Line]
    }

    private static let marker = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([0-9]{1,9})([.)])|([-•*+]))[ \t]+"#)

    private static func lines(_ source: String, codeRanges: [NSRange]) -> [Line] {
        let text = source as NSString
        var result: [Line] = []
        var location = 0
        let orderedCodeRanges = codeRanges.sorted { $0.location < $1.location }
        var codeIndex = 0
        var fence: (Character, Int)?
        repeat {
            var start = 0, end = 0, contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let range = NSRange(location: start, length: end - start)
            let content = text.substring(with: NSRange(location: start, length: contentsEnd - start))
            let whitespace = String(content.prefix { $0 == " " || $0 == "\t" })
            let columns = whitespace.reduce(0) { $1 == "\t" ? ($0 / 4 + 1) * 4 : $0 + 1 }
            let trimmed = content.dropFirst(whitespace.count)
            var fenced = fence != nil
            if let character = trimmed.first, character == "`" || character == "~" {
                let run = trimmed.prefix { $0 == character }.count
                if run >= 3 {
                    if let current = fence {
                        if current.0 == character, run >= current.1,
                           trimmed.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) { fence = nil }
                    } else {
                        fence = (character, run)
                        fenced = true
                    }
                }
            }
            let markerStart = start + whitespace.utf16.count
            while codeIndex < orderedCodeRanges.count, NSMaxRange(orderedCodeRanges[codeIndex]) <= markerStart { codeIndex += 1 }
            let code = fenced || (codeIndex < orderedCodeRanges.count && orderedCodeRanges[codeIndex].location < contentsEnd)
            var prefix: Prefix?
            if !code, let match = marker.firstMatch(in: content, range: NSRange(location: 0, length: content.utf16.count)) {
                let ns = content as NSString
                let digits = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
                prefix = Prefix(number: Int(digits), digits: digits,
                                delimiter: match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3)),
                                bullet: match.range(at: 4).location == NSNotFound ? "" : ns.substring(with: match.range(at: 4)))
            }
            result.append(Line(id: result.count, range: range, text: content, whitespace: whitespace,
                               columns: columns, prefix: prefix, isCode: code))
            if end == text.length {
                if contentsEnd < end { result.append(Line(id: result.count, range: NSRange(location: end, length: 0), text: "", whitespace: "", columns: 0, prefix: nil, isCode: false)) }
                break
            }
            location = end
        } while location <= text.length
        return result
    }

    private static func groups(_ lines: [Line]) -> [Group] {
        var result: [Group] = []
        var stack: [Line] = []
        var latest: [Container: Int] = [:]
        var boundary = -1
        for line in lines {
            guard let prefix = line.prefix else {
                if line.text.isEmpty { continue }
                if let root = stack.first, line.columns > root.columns { continue }
                stack.removeAll()
                latest.removeAll()
                boundary = line.id
                continue
            }
            while let previous = stack.last, previous.columns >= line.columns { stack.removeLast() }
            let container = Container(boundary: boundary, parent: stack.last?.id, columns: line.columns)
            if prefix.number != nil {
                if let index = latest[container], result[index].delimiter == prefix.delimiter {
                    result[index].members.append(line)
                } else {
                    result.append(Group(container: container, delimiter: prefix.delimiter, members: [line]))
                    latest[container] = result.count - 1
                }
            } else {
                latest.removeValue(forKey: container)
            }
            stack.append(line)
        }
        return result
    }

    private static func applying(_ edits: [Edit], to source: String) -> String {
        let result = NSMutableString(string: source)
        for edit in edits.reversed() { result.replaceCharacters(in: edit.range, with: edit.text) }
        return result as String
    }

    private static func map(_ position: Int, through edits: [Edit]) -> Int {
        var delta = 0
        for edit in edits {
            if position < edit.range.location { break }
            if position >= NSMaxRange(edit.range) { delta += edit.text.utf16.count - edit.range.length }
            else { return edit.range.location + delta + min(position - edit.range.location, edit.text.utf16.count) }
        }
        return position + delta
    }

    private static func map(_ range: NSRange, through edits: [Edit]) -> NSRange {
        let start = map(range.location, through: edits)
        return NSRange(location: start, length: max(0, map(NSMaxRange(range), through: edits) - start))
    }
}
