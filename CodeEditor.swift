import AppKit
import SwiftUI

// ═══════════════════════════════════════════════════════════════
// MARK: - Syntax Highlighter
// ═══════════════════════════════════════════════════════════════

final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()
    private var busy = false

    func apply(to tv: NSTextView, language: CodeLanguage) {
        guard !busy, let storage = tv.textStorage else { return }
        busy = true
        defer { busy = false }

        let str  = tv.string
        let full = NSRange(location: 0, length: (str as NSString).length)
        guard full.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ], range: full)

        switch language {
        case .json:       highlightJSON(storage, str)
        case .xml, .html: highlightXML(storage, str)
        case .sql:        highlightSQL(storage, str)
        case .css:        highlightCSS(storage, str)
        case .none:       break
        }
        storage.endEditing()
    }

    // MARK: Per-language rules

    private func highlightJSON(_ s: NSTextStorage, _ t: String) {
        rx(s, t, "\"(?:[^\"\\\\]|\\\\.)*\"\\s*:",                       .systemOrange)
        rx(s, t, "\"(?:[^\"\\\\]|\\\\.)*\"",                            .systemGreen)
        rx(s, t, "\\b-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b",        .systemBlue)
        rx(s, t, "\\b(true|false|null)\\b",                             .systemPurple)
    }

    private func highlightXML(_ s: NSTextStorage, _ t: String) {
        rx(s, t, "<!--[\\s\\S]*?-->",                                   .systemGray)
        rx(s, t, "\"[^\"]*\"",                                          .systemGreen)
        rx(s, t, "<[?!]?/?[\\w:.-]+(?:\\s[^>]*)?>",                    .systemBlue)
        rx(s, t, "\\b[\\w:-]+(?=\\s*=)",                                .systemOrange)
    }

    private func highlightSQL(_ s: NSTextStorage, _ t: String) {
        let kw = "SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|" +
                 "CREATE|TABLE|DROP|ALTER|JOIN|LEFT|RIGHT|INNER|OUTER|ON|" +
                 "AND|OR|NOT|IN|IS|NULL|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|" +
                 "AS|DISTINCT|UNION|ALL|EXISTS|BETWEEN|LIKE|PRIMARY|KEY|" +
                 "FOREIGN|REFERENCES|VARCHAR|INT|INTEGER|TEXT|BOOLEAN|FLOAT|" +
                 "DOUBLE|DATE|TIMESTAMP|INDEX|UNIQUE|DEFAULT|CONSTRAINT"
        rx(s, t, "\\b(\(kw))\\b",          .systemBlue, caseInsensitive: true)
        rx(s, t, "'[^']*'",                .systemGreen)
        rx(s, t, "--[^\n]*",               .systemGray)
        rx(s, t, "/\\*[\\s\\S]*?\\*/",     .systemGray)
        rx(s, t, "\\b\\d+(?:\\.\\d+)?\\b", .systemOrange)
    }

    private func highlightCSS(_ s: NSTextStorage, _ t: String) {
        rx(s, t, "/\\*[\\s\\S]*?\\*/",               .systemGray)
        rx(s, t, "[\\w.#:*\\[\\]=~^$|>+~,\\s]+(?=\\s*\\{)", .systemOrange)
        rx(s, t, "[\\w-]+(?=\\s*:)",                  .systemBlue)
        rx(s, t, "#[0-9a-fA-F]{3,8}\\b",             .systemPurple)
    }

    private func rx(_ s: NSTextStorage, _ t: String, _ pattern: String, _ color: NSColor, caseInsensitive: Bool = false) {
        let opts: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
        let range = NSRange(location: 0, length: (t as NSString).length)
        for m in re.matches(in: t, range: range) {
            s.addAttribute(.foregroundColor, value: color, range: m.range)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Line Number Ruler
// ═══════════════════════════════════════════════════════════════

final class LineNumberRulerView: NSRulerView {

    var errorLines: Set<Int> = []

    private let numFont      = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let numFontBold  = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    private let numColor     = NSColor.tertiaryLabelColor
    private let errorColor   = NSColor.systemRed
    private let errorBgColor = NSColor.systemRed.withAlphaComponent(0.10)

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 44
    }
    required init(coder: NSCoder) { fatalError() }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = (scrollView?.documentView as? NSTextView),
              let lm = tv.layoutManager,
              let sv = scrollView else { return }

        // Background
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        // Right separator
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        sep.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        sep.lineWidth = 1; sep.stroke()

        let vis   = sv.documentVisibleRect
        let inset = tv.textContainerInset.height
        let nsStr = tv.string as NSString
        let total = nsStr.length
        let attrs: [NSAttributedString.Key: Any] = [.font: numFont, .foregroundColor: numColor]

        if total == 0 {
            let s = "1" as NSString; let sz = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: ruleThickness - sz.width - 8, y: inset - vis.origin.y + 2), withAttributes: attrs)
            return
        }

        let errorAttrs: [NSAttributedString.Key: Any] = [.font: numFontBold, .foregroundColor: errorColor]

        var charIdx = 0
        var lineNum = 1
        var prev    = -1

        while charIdx <= total {
            guard charIdx != prev else { break }
            prev = charIdx

            let safe  = min(charIdx, total - 1)
            let glyph = lm.glyphIndexForCharacter(at: safe)
            guard glyph < lm.numberOfGlyphs else { break }

            var fragRange = NSRange()
            let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragRange)
            let drawY = frag.minY + inset - vis.origin.y

            if drawY > bounds.maxY { break }
            if drawY + frag.height > bounds.minY {
                let isError = errorLines.contains(lineNum)

                // Draw error background stripe across the ruler
                if isError {
                    errorBgColor.setFill()
                    NSRect(x: 0, y: drawY, width: bounds.width, height: frag.height).fill()
                }

                let useAttrs = isError ? errorAttrs : attrs
                let s = "\(lineNum)" as NSString
                let sz = s.size(withAttributes: useAttrs)
                s.draw(at: NSPoint(
                    x: ruleThickness - sz.width - 8,
                    y: drawY + (frag.height - sz.height) / 2
                ), withAttributes: useAttrs)
            }

            if charIdx >= total { break }
            let lr = nsStr.lineRange(for: NSRange(location: charIdx, length: 0))
            charIdx = NSMaxRange(lr)
            lineNum += 1
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Code Scroll View (hosts NSTextView + ruler)
// ═══════════════════════════════════════════════════════════════

final class CodeScrollView: NSScrollView {
    private(set) var codeTextView: NSTextView!
    private(set) var lineRuler: LineNumberRulerView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        hasVerticalScroller   = true
        hasHorizontalScroller = false
        autohidesScrollers    = false
        drawsBackground       = false
        borderType            = .noBorder

        let tv = NSTextView()
        tv.autoresizingMask        = [.width]
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView  = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.font       = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticSpellingCorrectionEnabled   = false
        tv.isAutomaticQuoteSubstitutionEnabled     = false
        tv.isAutomaticDashSubstitutionEnabled      = false
        tv.isAutomaticLinkDetectionEnabled         = false
        tv.usesFindBar                             = true
        tv.isIncrementalSearchingEnabled           = true

        documentView = tv
        codeTextView = tv
    }

    func enableLineNumbers() {
        let ruler = LineNumberRulerView(scrollView: self, orientation: .verticalRuler)
        ruler.clientView = codeTextView
        verticalRulerView = ruler
        rulersVisible     = true
        lineRuler         = ruler

        // Redraw on scroll
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                               object: contentView, queue: .main) { [weak ruler] _ in
            ruler?.needsDisplay = true
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - SwiftUI Wrapper
// ═══════════════════════════════════════════════════════════════

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var language: CodeLanguage = .none
    var isEditable: Bool       = true
    var showLineNumbers: Bool  = true
    var errorLines: Set<Int>   = []

    func makeNSView(context: Context) -> CodeScrollView {
        let sv = CodeScrollView(frame: .zero)
        sv.codeTextView.delegate   = context.coordinator
        sv.codeTextView.isEditable = isEditable
        if showLineNumbers { sv.enableLineNumbers() }
        return sv
    }

    func updateNSView(_ sv: CodeScrollView, context: Context) {
        let tv = sv.codeTextView!
        guard !context.coordinator.isEditing else { return }

        let textChanged  = tv.string != text
        let langChanged  = context.coordinator.lastLang != language
        let errorChanged = context.coordinator.lastErrorLines != errorLines

        if textChanged {
            let sel = tv.selectedRange()
            tv.string = text
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }

        if textChanged || langChanged || errorChanged {
            SyntaxHighlighter.shared.apply(to: tv, language: language)
            applyErrorHighlights(tv, lines: errorLines)
            context.coordinator.lastLang = language
            context.coordinator.lastErrorLines = errorLines
            sv.lineRuler?.errorLines = errorLines
            sv.lineRuler?.needsDisplay = true
        }

        if tv.isEditable != isEditable { tv.isEditable = isEditable }
    }

    private func applyErrorHighlights(_ tv: NSTextView, lines: Set<Int>) {
        guard let storage = tv.textStorage, !lines.isEmpty else { return }
        let nsStr = tv.string as NSString
        let total = nsStr.length
        guard total > 0 else { return }

        let errorBg = NSColor.systemRed.withAlphaComponent(0.10)
        var charIdx = 0
        var lineNum = 1

        while charIdx < total {
            let lineRange = nsStr.lineRange(for: NSRange(location: charIdx, length: 0))
            if lines.contains(lineNum) {
                storage.addAttribute(.backgroundColor, value: errorBg, range: lineRange)
            }
            let next = NSMaxRange(lineRange)
            if next <= charIdx { break }
            charIdx = next
            lineNum += 1
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        var isEditing = false
        var lastLang: CodeLanguage = .none
        var lastErrorLines: Set<Int> = []

        init(_ p: CodeEditor) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = tv.string
            SyntaxHighlighter.shared.apply(to: tv, language: parent.language)
            (tv.enclosingScrollView as? CodeScrollView)?.lineRuler?.needsDisplay = true
            DispatchQueue.main.async { self.isEditing = false }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            (tv.enclosingScrollView as? CodeScrollView)?.lineRuler?.needsDisplay = true
        }
    }
}
