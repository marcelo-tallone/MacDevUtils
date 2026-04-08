import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════
// MARK: - Diff Types
// ═══════════════════════════════════════════════════════════════

enum DiffType {
    case equal
    case added
    case removed
    case changed
}

/// A segment of text within a line, either matching or different
struct InlineSegment: Identifiable {
    let id = UUID()
    let text: String
    let isDiff: Bool
}

/// A single row in the side-by-side diff view
struct DiffRow: Identifiable {
    let id = UUID()
    let type: DiffType
    let leftLineNum: Int?
    let leftText: String?
    let rightLineNum: Int?
    let rightText: String?
    // For changed lines: inline character-level diff segments
    var leftSegments: [InlineSegment]?
    var rightSegments: [InlineSegment]?
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Diff Engine (LCS with trimmed comparison)
// ═══════════════════════════════════════════════════════════════

struct DiffEngine {

    static func compare(left: String, right: String) -> [DiffRow] {
        let leftLines = left.components(separatedBy: "\n")
        let rightLines = right.components(separatedBy: "\n")
        let m = leftLines.count
        let n = rightLines.count

        // Build LCS table comparing lines exactly
        var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) where i <= m {
            for j in 1...max(n, 1) where j <= n {
                if leftLines[i - 1] == rightLines[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }

        // Trace back to build diff
        var rows: [DiffRow] = []
        var i = m, j = n

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && leftLines[i - 1] == rightLines[j - 1] {
                rows.append(DiffRow(type: .equal,
                                    leftLineNum: i, leftText: leftLines[i - 1],
                                    rightLineNum: j, rightText: rightLines[j - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || table[i][j - 1] >= table[i - 1][j]) {
                rows.append(DiffRow(type: .added,
                                    leftLineNum: nil, leftText: nil,
                                    rightLineNum: j, rightText: rightLines[j - 1]))
                j -= 1
            } else if i > 0 {
                rows.append(DiffRow(type: .removed,
                                    leftLineNum: i, leftText: leftLines[i - 1],
                                    rightLineNum: nil, rightText: nil))
                i -= 1
            }
        }

        rows.reverse()

        // Post-process: collect adjacent blocks of removed/added and pair them as "changed"
        var merged: [DiffRow] = []
        var idx = 0
        while idx < rows.count {
            // Collect a contiguous block of removes
            var removes: [DiffRow] = []
            while idx < rows.count && rows[idx].type == .removed {
                removes.append(rows[idx]); idx += 1
            }
            // Collect a contiguous block of adds right after
            var adds: [DiffRow] = []
            while idx < rows.count && rows[idx].type == .added {
                adds.append(rows[idx]); idx += 1
            }

            // Pair removes and adds as "changed" only if they are similar enough
            var usedRemoves = Array(repeating: false, count: removes.count)
            var usedAdds = Array(repeating: false, count: adds.count)
            var pairs: [(Int, Int)] = [] // (remove index, add index)

            // For each remove, find the best matching add (highest similarity)
            for r in 0..<removes.count {
                let lt = (removes[r].leftText ?? "").trimmingCharacters(in: .whitespaces)
                var bestIdx = -1
                var bestScore: Double = 0
                for a in 0..<adds.count {
                    guard !usedAdds[a] else { continue }
                    let rt = (adds[a].rightText ?? "").trimmingCharacters(in: .whitespaces)
                    let score = similarity(lt, rt)
                    if score > bestScore { bestScore = score; bestIdx = a }
                }
                // Only pair if similarity > 40%
                if bestIdx >= 0 && bestScore > 0.4 {
                    pairs.append((r, bestIdx))
                    usedRemoves[r] = true
                    usedAdds[bestIdx] = true
                }
            }

            // Emit in order: process all removes and adds by their original position
            // Build a combined timeline
            var rIdx = 0, aIdx = 0
            let sortedPairs = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })

            for r in 0..<removes.count {
                if let a = sortedPairs[r] {
                    // Emit any unpaired adds that come before this paired add
                    while aIdx < a {
                        if !usedAdds[aIdx] { merged.append(adds[aIdx]) }
                        aIdx += 1
                    }
                    // Emit the changed pair
                    let lt = removes[r].leftText ?? ""
                    let rt = adds[a].rightText ?? ""
                    let (leftSegs, rightSegs) = inlineDiff(left: lt, right: rt)
                    merged.append(DiffRow(type: .changed,
                                          leftLineNum: removes[r].leftLineNum,
                                          leftText: lt,
                                          rightLineNum: adds[a].rightLineNum,
                                          rightText: rt,
                                          leftSegments: leftSegs,
                                          rightSegments: rightSegs))
                    aIdx = a + 1
                } else {
                    merged.append(removes[r])
                }
            }
            // Emit remaining unpaired adds
            while aIdx < adds.count {
                if !usedAdds[aIdx] { merged.append(adds[aIdx]) }
                aIdx += 1
            }

            // If we didn't consume anything (equal row), just add it
            if removes.isEmpty && adds.isEmpty {
                merged.append(rows[idx])
                idx += 1
            }
        }

        return merged
    }

    /// Character-level LCS diff between two strings, returns segments for each side
    private static func inlineDiff(left: String, right: String) -> ([InlineSegment], [InlineSegment]) {
        let a = Array(left)
        let b = Array(right)
        let m = a.count
        let n = b.count

        // LCS at character level
        var table = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) where i <= m {
            for j in 1...max(n, 1) where j <= n {
                if a[i - 1] == b[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }

        // Trace back
        enum CharOp { case equal(Character), removed(Character), added(Character) }
        var ops: [CharOp] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                ops.append(.equal(a[i - 1])); i -= 1; j -= 1
            } else if j > 0 && (i == 0 || table[i][j - 1] >= table[i - 1][j]) {
                ops.append(.added(b[j - 1])); j -= 1
            } else {
                ops.append(.removed(a[i - 1])); i -= 1
            }
        }
        ops.reverse()

        // Build left segments (equal + removed)
        var leftSegs: [InlineSegment] = []
        var buf = ""
        var bufIsDiff = false
        for op in ops {
            switch op {
            case .equal(let c):
                if bufIsDiff && !buf.isEmpty { leftSegs.append(InlineSegment(text: buf, isDiff: true)); buf = "" }
                bufIsDiff = false; buf.append(c)
            case .removed(let c):
                if !bufIsDiff && !buf.isEmpty { leftSegs.append(InlineSegment(text: buf, isDiff: false)); buf = "" }
                bufIsDiff = true; buf.append(c)
            case .added:
                break
            }
        }
        if !buf.isEmpty { leftSegs.append(InlineSegment(text: buf, isDiff: bufIsDiff)) }

        // Build right segments (equal + added)
        var rightSegs: [InlineSegment] = []
        buf = ""; bufIsDiff = false
        for op in ops {
            switch op {
            case .equal(let c):
                if bufIsDiff && !buf.isEmpty { rightSegs.append(InlineSegment(text: buf, isDiff: true)); buf = "" }
                bufIsDiff = false; buf.append(c)
            case .added(let c):
                if !bufIsDiff && !buf.isEmpty { rightSegs.append(InlineSegment(text: buf, isDiff: false)); buf = "" }
                bufIsDiff = true; buf.append(c)
            case .removed:
                break
            }
        }
        if !buf.isEmpty { rightSegs.append(InlineSegment(text: buf, isDiff: bufIsDiff)) }

        return (leftSegs, rightSegs)
    }

    /// Returns a similarity score between 0 and 1 based on LCS length vs max string length
    private static func similarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        let ac = Array(a), bc = Array(b)
        let m = ac.count, n = bc.count
        // Quick LCS length calculation
        var prev = Array(repeating: 0, count: n + 1)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...max(m, 1) where i <= m {
            for j in 1...max(n, 1) where j <= n {
                if ac[i - 1] == bc[j - 1] {
                    curr[j] = prev[j - 1] + 1
                } else {
                    curr[j] = max(prev[j], curr[j - 1])
                }
            }
            prev = curr
            curr = Array(repeating: 0, count: n + 1)
        }
        let lcsLen = prev[n]
        return Double(lcsLen) / Double(max(m, n))
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Compare View
// ═══════════════════════════════════════════════════════════════

struct CompareView: View {
    @State private var leftText = ""
    @State private var rightText = ""
    @State private var diffRows: [DiffRow] = []
    @State private var hasCompared = false
    @State private var leftFileName = "Texto izquierdo"
    @State private var rightFileName = "Texto derecho"
    @State private var diffStats = DiffStats()

    struct DiffStats {
        var added = 0
        var removed = 0
        var changed = 0
        var equal = 0
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if hasCompared {
                diffResultView
            } else {
                inputPanels
            }

            Divider()
            statusBar
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: loadLeftFile) {
                Label("Abrir izquierdo", systemImage: "doc")
            }

            Button(action: loadRightFile) {
                Label("Abrir derecho", systemImage: "doc")
            }

            Divider().frame(height: 18)

            Button(action: compare) {
                Label("Comparar", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(leftText.isEmpty && rightText.isEmpty)

            if hasCompared {
                Button(action: backToEdit) {
                    Label("Editar textos", systemImage: "pencil")
                }

                Button(action: swapTexts) {
                    Label("Intercambiar", systemImage: "arrow.left.arrow.right")
                }
            }

            Button(action: clear) {
                Label("Limpiar", systemImage: "trash")
            }

            Spacer()

            if hasCompared {
                HStack(spacing: 12) {
                    statBadge("+\(diffStats.added)", color: .green)
                    statBadge("-\(diffStats.removed)", color: .red)
                    statBadge("~\(diffStats.changed)", color: .orange)
                    statBadge("=\(diffStats.equal)", color: .secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func statBadge(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.3)).frame(width: 10, height: 10)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
        }
    }

    // MARK: - Input Panels

    private var inputPanels: some View {
        HSplitView {
            VStack(spacing: 0) {
                panelHeader(leftFileName, side: "Izquierdo")
                CodeEditor(text: $leftText, language: .none, showLineNumbers: true)
            }
            VStack(spacing: 0) {
                panelHeader(rightFileName, side: "Derecho")
                CodeEditor(text: $rightText, language: .none, showLineNumbers: true)
            }
        }
    }

    @ViewBuilder
    private func panelHeader(_ title: String, side: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(side)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
        Divider()
    }

    // MARK: - Diff Result View (side by side, synchronized)

    private var diffResultView: some View {
        HSplitView {
            VStack(spacing: 0) {
                panelHeader(leftFileName, side: "Original")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffRows) { row in
                            leftDiffRow(row)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }

            VStack(spacing: 0) {
                panelHeader(rightFileName, side: "Modificado")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffRows) { row in
                            rightDiffRow(row)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
    }

    private func leftDiffRow(_ row: DiffRow) -> some View {
        switch row.type {
        case .equal:
            return diffLineContent(lineNum: row.leftLineNum, segments: nil, text: row.leftText ?? "",
                                   bgColor: .clear, type: .equal, isPlaceholder: false)
        case .removed:
            return diffLineContent(lineNum: row.leftLineNum, segments: nil, text: row.leftText ?? "",
                                   bgColor: Color.red.opacity(0.12), type: .removed, isPlaceholder: false)
        case .changed:
            return diffLineContent(lineNum: row.leftLineNum, segments: row.leftSegments, text: row.leftText ?? "",
                                   bgColor: Color.orange.opacity(0.08), type: .changed, isPlaceholder: false)
        case .added:
            return diffLineContent(lineNum: nil, segments: nil, text: "",
                                   bgColor: Color(NSColor.controlBackgroundColor).opacity(0.3), type: .added, isPlaceholder: true)
        }
    }

    private func rightDiffRow(_ row: DiffRow) -> some View {
        switch row.type {
        case .equal:
            return diffLineContent(lineNum: row.rightLineNum, segments: nil, text: row.rightText ?? "",
                                   bgColor: .clear, type: .equal, isPlaceholder: false)
        case .added:
            return diffLineContent(lineNum: row.rightLineNum, segments: nil, text: row.rightText ?? "",
                                   bgColor: Color.green.opacity(0.12), type: .added, isPlaceholder: false)
        case .changed:
            return diffLineContent(lineNum: row.rightLineNum, segments: row.rightSegments, text: row.rightText ?? "",
                                   bgColor: Color.orange.opacity(0.08), type: .changed, isPlaceholder: false)
        case .removed:
            return diffLineContent(lineNum: nil, segments: nil, text: "",
                                   bgColor: Color(NSColor.controlBackgroundColor).opacity(0.3), type: .removed, isPlaceholder: true)
        }
    }

    private func diffLineContent(lineNum: Int?, segments: [InlineSegment]?, text: String,
                                 bgColor: Color, type: DiffType, isPlaceholder: Bool) -> some View {
        HStack(spacing: 0) {
            // Line number column
            Text(lineNum.map { String($0) } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)

            // Indicator
            Text(indicatorFor(type, isPlaceholder: isPlaceholder))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(colorFor(type))
                .frame(width: 16)

            // Text content - use inline segments for changed lines
            if let segs = segments, !isPlaceholder {
                inlineSegmentsView(segs, type: type)
            } else {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(isPlaceholder ? .clear : Color(NSColor.labelColor))
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
        .padding(.horizontal, 4)
        .background(bgColor)
    }

    private func inlineSegmentsView(_ segments: [InlineSegment], type: DiffType) -> some View {
        let highlightColor = NSColor.systemOrange.withAlphaComponent(0.4)
        var result = AttributedString()
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let monoFontBold = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        for seg in segments {
            var part = AttributedString(seg.text)
            part.foregroundColor = Color(NSColor.labelColor)
            if seg.isDiff {
                part.font = monoFontBold
                part.backgroundColor = Color(highlightColor)
            } else {
                part.font = monoFont
            }
            result += part
        }
        return Text(result).textSelection(.enabled)
    }

    private func indicatorFor(_ type: DiffType, isPlaceholder: Bool) -> String {
        if isPlaceholder { return " " }
        switch type {
        case .equal:   return " "
        case .added:   return "+"
        case .removed: return "-"
        case .changed: return "~"
        }
    }

    private func colorFor(_ type: DiffType) -> Color {
        switch type {
        case .equal:   return .secondary
        case .added:   return .green
        case .removed: return .red
        case .changed: return .orange
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            if hasCompared {
                let total = diffStats.added + diffStats.removed + diffStats.changed + diffStats.equal
                Text("\(total) líneas comparadas")
                    .font(.system(size: 11))

                Divider().frame(height: 12)

                Text("\(diffStats.equal) iguales, \(diffStats.changed) modificadas, \(diffStats.added) agregadas, \(diffStats.removed) eliminadas")
                    .font(.system(size: 11))
            } else {
                let leftLines = max(1, leftText.components(separatedBy: "\n").count)
                let rightLines = max(1, rightText.components(separatedBy: "\n").count)
                Text("Izquierdo: \(leftLines) líneas")
                    .font(.system(size: 11))
                Divider().frame(height: 12)
                Text("Derecho: \(rightLines) líneas")
                    .font(.system(size: 11))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .foregroundColor(.secondary)
    }

    // MARK: - Actions

    private func compare() {
        diffRows = DiffEngine.compare(left: leftText, right: rightText)
        diffStats = DiffStats(
            added: diffRows.filter { $0.type == .added }.count,
            removed: diffRows.filter { $0.type == .removed }.count,
            changed: diffRows.filter { $0.type == .changed }.count,
            equal: diffRows.filter { $0.type == .equal }.count
        )
        hasCompared = true
    }

    private func backToEdit() {
        hasCompared = false
        diffRows = []
    }

    private func swapTexts() {
        let tmp = leftText
        leftText = rightText
        rightText = tmp
        let tmpName = leftFileName
        leftFileName = rightFileName
        rightFileName = tmpName
        if hasCompared { compare() }
    }

    private func clear() {
        leftText = ""
        rightText = ""
        diffRows = []
        hasCompared = false
        leftFileName = "Texto izquierdo"
        rightFileName = "Texto derecho"
        diffStats = DiffStats()
    }

    private func loadLeftFile() {
        if let (name, content) = openFilePanel() {
            leftText = content
            leftFileName = name
            if hasCompared { compare() }
        }
    }

    private func loadRightFile() {
        if let (name, content) = openFilePanel() {
            rightText = content
            rightFileName = name
            if hasCompared { compare() }
        }
    }

    private func openFilePanel() -> (String, String)? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (url.lastPathComponent, content)
    }
}
