//
//  MarkdownTableEditor.swift
//  md-preview
//

import Foundation

enum MarkdownTableEditor {
    struct Snapshot {
        let tableIndex: Int
        let rows: [[String]]
        let dirtyRows: [[Bool]]?

        init(tableIndex: Int, rows: [[String]], dirtyRows: [[Bool]]? = nil) {
            self.tableIndex = tableIndex
            self.rows = rows
            self.dirtyRows = dirtyRows
        }
    }

    static func replacingTable(in markdown: String, with snapshot: Snapshot) -> String? {
        guard !snapshot.rows.isEmpty,
              let table = tables(in: markdown).dropFirst(snapshot.tableIndex).first
        else { return nil }

        let replacement = makeMarkdownTable(snapshot: snapshot, source: table)
        var result = markdown
        result.replaceSubrange(table.range, with: replacement)
        return result
    }

    private struct SourceTable {
        let range: Range<String.Index>
        let alignments: [String]
        let rows: [[String]]
        let quotePrefix: String?
    }

    private struct Fence {
        let marker: Character
        let length: Int
    }

    private static func makeMarkdownTable(snapshot: Snapshot, source: SourceTable) -> String {
        let rows = snapshot.rows
        let columnCount = max(1, rows.map(\.count).max() ?? 1)
        let normalizedRows = rows.enumerated().map { rowIndex, row in
            (0..<columnCount).map { index in
                if isDirty(row: rowIndex, column: index, snapshot: snapshot)
                    || rowIndex >= source.rows.count
                    || index >= source.rows[rowIndex].count {
                    return index < row.count ? escapeCell(row[index]) : ""
                }
                return source.rows[rowIndex][index].trimmingCharacters(in: .whitespaces)
            }
        }
        let header = normalizedRows.first ?? Array(repeating: "", count: columnCount)
        let body = normalizedRows.dropFirst()
        let separator = (0..<columnCount).map { index in
            index < source.alignments.count ? source.alignments[index] : "---"
        }

        return ([header, separator] + body).map { row in
            (source.quotePrefix ?? "") + "| " + row.joined(separator: " | ") + " |"
        }.joined(separator: "\n")
    }

    private static func isDirty(row: Int, column: Int, snapshot: Snapshot) -> Bool {
        guard let dirtyRows = snapshot.dirtyRows else { return true }
        guard row < dirtyRows.count, column < dirtyRows[row].count else { return true }
        return dirtyRows[row][column]
    }

    private static func escapeCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func tables(in markdown: String) -> [SourceTable] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var tables: [SourceTable] = []
        var lineStarts: [String.Index] = []
        var cursor = markdown.startIndex

        for line in lines {
            lineStarts.append(cursor)
            cursor = markdown.index(cursor, offsetBy: line.count)
            if cursor < markdown.endIndex, markdown[cursor] == "\n" {
                cursor = markdown.index(after: cursor)
            }
        }

        var fence: Fence?
        var index = 0
        while index < lines.count {
            let line = String(lines[index])
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isIndentedCode(line) {
                index += 1
                continue
            }
            if let activeFence = fence {
                if closesFence(trimmed, activeFence) {
                    fence = nil
                }
                index += 1
                continue
            } else if let openingFence = fenceStart(in: trimmed) {
                fence = openingFence
                index += 1
                continue
            }

            guard index + 1 < lines.count,
                  let headerLine = normalizedTableLine(line),
                  let separatorLine = normalizedTableLine(String(lines[index + 1])),
                  let headerCells = splitTableRow(headerLine.content),
                  hasTableDelimiter(headerLine.content),
                  let separator = parseSeparatorRow(separatorLine.content),
                  headerLine.quotePrefix == separatorLine.quotePrefix,
                  separator.count == headerCells.count
            else {
                index += 1
                continue
            }

            let startLine = index
            index += 2
            while index < lines.count,
                  !isIndentedCode(String(lines[index])),
                  normalizedTableLine(String(lines[index]))?.quotePrefix == headerLine.quotePrefix,
                  splitTableRow(normalizedTableLine(String(lines[index]))?.content ?? "") != nil {
                index += 1
            }

            let start = lineStarts[startLine]
            let end = index < lineStarts.count ? previousLineEnd(before: lineStarts[index], in: markdown) : markdown.endIndex
            let tableLines = Array(lines[startLine..<index])
            let rowCells = tableLines.enumerated().compactMap { offset, raw -> [String]? in
                guard offset != 1,
                      let normalized = normalizedTableLine(String(raw)),
                      normalized.quotePrefix == headerLine.quotePrefix
                else { return nil }
                return splitTableRow(normalized.content)
            }
            tables.append(SourceTable(
                range: start..<end,
                alignments: separator,
                rows: rowCells,
                quotePrefix: headerLine.quotePrefix
            ))
        }

        return tables
    }

    private static func previousLineEnd(before index: String.Index, in markdown: String) -> String.Index {
        guard index > markdown.startIndex else { return index }
        let previous = markdown.index(before: index)
        return markdown[previous] == "\n" ? previous : index
    }

    private static func fenceStart(in trimmed: String) -> Fence? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        return count >= 3 ? Fence(marker: first, length: count) : nil
    }

    private static func closesFence(_ trimmed: String, _ fence: Fence) -> Bool {
        guard trimmed.first == fence.marker else { return false }
        let count = trimmed.prefix { $0 == fence.marker }.count
        guard count >= fence.length else { return false }
        return trimmed.dropFirst(count).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func isIndentedCode(_ line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        var count = 0
        for ch in line {
            if ch == " " {
                count += 1
                if count >= 4 { return true }
            } else if ch == "\t" {
                return true
            } else {
                return false
            }
        }
        return false
    }

    private static func normalizedTableLine(_ line: String) -> (content: String, quotePrefix: String?)? {
        if let quote = blockquotePrefix(in: line) {
            return (String(line.dropFirst(quote.count)), quote)
        }
        return (line, nil)
    }

    private static func blockquotePrefix(in line: String) -> String? {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " {
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == ">" else { return nil }
        let afterMarker = line.index(after: index)
        if afterMarker < line.endIndex, line[afterMarker] == " " {
            return String(line[..<line.index(after: afterMarker)])
        }
        return String(line[..<afterMarker])
    }

    private static func parseSeparatorRow(_ line: String) -> [String]? {
        guard let cells = splitTableRow(line), !cells.isEmpty else { return nil }
        let separators = cells.map { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 3 else { return "" }
            let body = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard body.count >= 3 && body.allSatisfy({ $0 == "-" }) else { return "" }
            let left = trimmed.first == ":"
            let right = trimmed.last == ":"
            switch (left, right) {
            case (true, true): return ":---:"
            case (true, false): return ":---"
            case (false, true): return "---:"
            case (false, false): return "---"
            }
        }
        return separators.contains("") ? nil : separators
    }

    private static func hasTableDelimiter(_ line: String) -> Bool {
        var escaped = false
        for ch in line {
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                return true
            }
        }
        return false
    }

    private static func splitTableRow(_ line: String) -> [String]? {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard hasTableDelimiter(text) else { return nil }
        if text.first == "|" {
            text.removeFirst()
        }
        if text.last == "|", !isEscapedTrailingPipe(text) {
            text.removeLast()
        }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in text {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                current.append(ch)
                escaped = true
            } else if ch == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current)
        return cells
    }

    private static func isEscapedTrailingPipe(_ text: String) -> Bool {
        var backslashCount = 0
        var index = text.index(before: text.endIndex)
        while index > text.startIndex {
            let previous = text.index(before: index)
            if text[previous] == "\\" {
                backslashCount += 1
                index = previous
            } else {
                break
            }
        }
        return backslashCount % 2 == 1
    }
}

enum MarkdownTaskListEditor {
    static func togglingTask(in markdown: String, taskIndex: Int, checked: Bool) -> String? {
        guard taskIndex >= 0 else { return nil }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var lineStarts: [String.Index] = []
        var cursor = markdown.startIndex

        for line in lines {
            lineStarts.append(cursor)
            cursor = markdown.index(cursor, offsetBy: line.count)
            if cursor < markdown.endIndex, markdown[cursor] == "\n" {
                cursor = markdown.index(after: cursor)
            }
        }

        var fence: Fence?
        var currentTaskIndex = 0
        for (lineIndex, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isIndentedCode(line) {
                continue
            }
            if let activeFence = fence {
                if closesFence(trimmed, activeFence) {
                    fence = nil
                }
                continue
            } else if let openingFence = fenceStart(in: trimmed) {
                fence = openingFence
                continue
            }

            guard let marker = taskMarkerRange(in: line) else { continue }
            if currentTaskIndex == taskIndex {
                let start = markdown.index(lineStarts[lineIndex], offsetBy: marker.lowerBound)
                let end = markdown.index(lineStarts[lineIndex], offsetBy: marker.upperBound)
                var result = markdown
                result.replaceSubrange(start..<end, with: checked ? "x" : " ")
                return result
            }
            currentTaskIndex += 1
        }

        return nil
    }

    private struct Fence {
        let marker: Character
        let length: Int
    }

    private static func taskMarkerRange(in line: String) -> Range<Int>? {
        let characters = Array(line)
        var index = 0
        while index < characters.count, characters[index] == " " {
            index += 1
        }
        guard index < 4 else { return nil }

        while index < characters.count, characters[index] == ">" {
            index += 1
            if index < characters.count, characters[index] == " " {
                index += 1
            }
        }

        guard index < characters.count else { return nil }
        if characters[index] == "-" || characters[index] == "+" || characters[index] == "*" {
            index += 1
        } else {
            let numberStart = index
            while index < characters.count, characters[index].isNumber {
                index += 1
            }
            guard index > numberStart,
                  index < characters.count,
                  characters[index] == "." || characters[index] == ")"
            else { return nil }
            index += 1
        }

        guard index < characters.count,
              characters[index] == " " || characters[index] == "\t"
        else { return nil }
        index += 1

        guard index + 2 < characters.count,
              characters[index] == "[",
              characters[index + 2] == "]",
              characters[index + 1] == " " || characters[index + 1].lowercased() == "x"
        else { return nil }

        return (index + 1)..<(index + 2)
    }

    private static func fenceStart(in trimmed: String) -> Fence? {
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let count = trimmed.prefix { $0 == first }.count
        return count >= 3 ? Fence(marker: first, length: count) : nil
    }

    private static func closesFence(_ trimmed: String, _ fence: Fence) -> Bool {
        guard trimmed.first == fence.marker else { return false }
        let count = trimmed.prefix { $0 == fence.marker }.count
        guard count >= fence.length else { return false }
        return trimmed.dropFirst(count).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func isIndentedCode(_ line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        var count = 0
        for ch in line {
            if ch == " " {
                count += 1
                if count >= 4 { return true }
            } else if ch == "\t" {
                return true
            } else {
                return false
            }
        }
        return false
    }
}

struct RenderedEditHistory: Equatable {
    struct Edit: Equatable {
        let before: String
        let after: String
        let actionName: String
    }

    private(set) var undoStack: [Edit] = []
    private(set) var redoStack: [Edit] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var nextUndoActionName: String? { undoStack.last?.actionName }
    var nextRedoActionName: String? { redoStack.last?.actionName }

    mutating func record(before: String?, after: String, actionName: String) {
        guard let before, before != after else { return }
        undoStack.append(Edit(before: before, after: after, actionName: actionName))
        redoStack.removeAll()
    }

    mutating func undo() -> Edit? {
        guard let edit = undoStack.popLast() else { return nil }
        redoStack.append(edit)
        return edit
    }

    mutating func redo() -> Edit? {
        guard let edit = redoStack.popLast() else { return nil }
        undoStack.append(edit)
        return edit
    }

    mutating func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
