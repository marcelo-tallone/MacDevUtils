import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════
// MARK: - Tab Model
// ═══════════════════════════════════════════════════════════════

final class EditorTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var text: String
    @Published var language: CodeLanguage
    @Published var fileURL: URL?
    @Published var isModified: Bool = false
    @Published var cursorLine: Int = 1
    @Published var cursorColumn: Int = 1
    @Published var wordWrap: Bool = true

    var displayTitle: String {
        (isModified ? "● " : "") + title
    }

    init(title: String = "Sin título", text: String = "", language: CodeLanguage = .none, fileURL: URL? = nil) {
        self.title = title
        self.text = text
        self.language = language
        self.fileURL = fileURL
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Editor State
// ═══════════════════════════════════════════════════════════════

final class EditorState: ObservableObject {
    @Published var tabs: [EditorTab] = []
    @Published var selectedTabID: UUID?

    var currentTab: EditorTab? {
        guard let id = selectedTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    init() {
        let first = EditorTab()
        tabs = [first]
        selectedTabID = first.id
    }

    func newTab() {
        let tab = EditorTab()
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            let wasSelected = (selectedTabID == id)
            tabs.remove(at: idx)
            if wasSelected {
                let newIdx = min(idx, tabs.count - 1)
                selectedTabID = tabs[newIdx].id
            }
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .json, .xml, .html, .sourceCode, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }

    func loadFile(_ url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lang = languageFromExtension(url.pathExtension)
        let tab = EditorTab(title: url.lastPathComponent, text: content, language: lang, fileURL: url)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func saveCurrentTab() {
        guard let tab = currentTab else { return }
        if let url = tab.fileURL {
            try? tab.text.write(to: url, atomically: true, encoding: .utf8)
            tab.isModified = false
        } else {
            saveCurrentTabAs()
        }
    }

    func saveCurrentTabAs() {
        guard let tab = currentTab else { return }
        let panel = NSSavePanel()
        let defaultName = tab.title.contains(".") ? tab.title : tab.title + ".txt"
        panel.nameFieldStringValue = defaultName
        panel.allowsOtherFileTypes = true
        panel.allowedContentTypes = []
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // If user typed a name with extension, use it as-is
        let finalURL: URL
        if url.pathExtension.isEmpty {
            finalURL = url.appendingPathExtension("txt")
        } else {
            finalURL = url
        }
        try? tab.text.write(to: finalURL, atomically: true, encoding: .utf8)
        tab.fileURL = finalURL
        tab.title = finalURL.lastPathComponent
        tab.isModified = false
        tab.language = languageFromExtension(finalURL.pathExtension)
    }

    private func languageFromExtension(_ ext: String) -> CodeLanguage {
        switch ext.lowercased() {
        case "json":                    return .json
        case "xml", "plist", "svg":     return .xml
        case "html", "htm":             return .html
        case "sql":                     return .sql
        case "css":                     return .css
        default:                        return .none
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Editor View
// ═══════════════════════════════════════════════════════════════

struct EditorView: View {
    @StateObject private var state = EditorState()
    @State private var showFind = false
    @State private var showReplace = false
    @State private var findText = ""
    @State private var replaceText = ""

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            Divider()
            tabBar
            Divider()

            ZStack {
                if let tab = state.currentTab {
                    EditorTabContent(tab: tab, showFind: $showFind, showReplace: $showReplace,
                                     findText: $findText, replaceText: $replaceText)
                        .id(tab.id)
                } else {
                    Text("Sin pestañas abiertas")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            statusBar
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileFromFinder)) { notif in
            if let url = notif.object as? URL {
                state.loadFile(url)
            }
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 10) {
            Button(action: state.newTab) {
                Label("Nuevo", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(action: state.openFile) {
                Label("Abrir", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(action: state.saveCurrentTab) {
                Label("Guardar", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)

            Button(action: state.saveCurrentTabAs) {
                Label("Guardar como…", systemImage: "square.and.arrow.down.on.square")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider().frame(height: 18)

            Button(action: { showFind.toggle(); if !showFind { showReplace = false } }) {
                Label("Buscar", systemImage: "magnifyingglass")
            }
            .keyboardShortcut("f", modifiers: .command)

            Button(action: { showReplace.toggle(); showFind = showReplace }) {
                Label("Reemplazar", systemImage: "arrow.left.arrow.right")
            }
            .keyboardShortcut("h", modifiers: .command)

            Divider().frame(height: 18)

            if let tab = state.currentTab {
                Button(action: { tab.wordWrap.toggle() }) {
                    Label("Ajuste de línea", systemImage: "text.word.spacing")
                }

                Picker("Lenguaje", selection: Binding(
                    get: { tab.language },
                    set: { tab.language = $0 }
                )) {
                    ForEach(CodeLanguage.allCases, id: \.self) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .frame(width: 130)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.tabs) { tab in
                    TabItemView(tab: tab, isSelected: state.selectedTabID == tab.id,
                                canClose: state.tabs.count > 1,
                                onSelect: { state.selectedTabID = tab.id },
                                onClose: { state.closeTab(tab.id) })
                }
                Spacer()
            }
        }
        .frame(height: 30)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            if let tab = state.currentTab {
                Text("Ln \(tab.cursorLine), Col \(tab.cursorColumn)")
                    .font(.system(size: 11, design: .monospaced))

                Divider().frame(height: 12)

                let charCount = tab.text.count
                let lineCount = max(1, tab.text.components(separatedBy: "\n").count)
                Text("\(charCount) caracteres")
                    .font(.system(size: 11))
                Text("\(lineCount) líneas")
                    .font(.system(size: 11))

                Divider().frame(height: 12)

                Text(tab.language.rawValue)
                    .font(.system(size: 11))

                Divider().frame(height: 12)

                Text("UTF-8")
                    .font(.system(size: 11))

                if tab.isModified {
                    Divider().frame(height: 12)
                    Text("Modificado")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .foregroundColor(.secondary)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Tab Item View
// ═══════════════════════════════════════════════════════════════

struct TabItemView: View {
    @ObservedObject var tab: EditorTab
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayTitle)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay(
            Rectangle()
                .frame(height: isSelected ? 2 : 0)
                .foregroundColor(.accentColor),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Editor Tab Content (text area + find bar)
// ═══════════════════════════════════════════════════════════════

// Shared reference to the editor's NSTextView so find/replace can access it
// without relying on window focus or responder chain.
final class EditorTextViewRef: ObservableObject {
    weak var textView: NSTextView?
}

struct EditorTabContent: View {
    @ObservedObject var tab: EditorTab
    @Binding var showFind: Bool
    @Binding var showReplace: Bool
    @Binding var findText: String
    @Binding var replaceText: String

    @StateObject private var tvRef = EditorTextViewRef()
    @State private var matchCount: Int = 0
    @State private var matchCase: Bool = false
    @State private var wholeWord: Bool = false
    @State private var useRegex: Bool = false
    @State private var regexError: String? = nil
    @FocusState private var findFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showFind {
                findBar
                Divider()
            }

            EditorCodeArea(tab: tab, tvRef: tvRef)
        }
    }

    // MARK: Search options helper

    private var searchOptions: NSString.CompareOptions {
        var opts: NSString.CompareOptions = []
        if !matchCase { opts.insert(.caseInsensitive) }
        if useRegex { opts.insert(.regularExpression) }
        return opts
    }

    private func buildSearchPattern() -> String {
        var pattern = findText
        if useRegex {
            // Validate regex
            do {
                _ = try NSRegularExpression(pattern: pattern)
                regexError = nil
            } catch {
                regexError = error.localizedDescription
                return pattern
            }
        }
        if wholeWord && !useRegex {
            pattern = "\\b" + NSRegularExpression.escapedPattern(for: pattern) + "\\b"
            // wholeWord needs regex mode internally
        }
        return pattern
    }

    private var effectiveOptions: NSString.CompareOptions {
        var opts: NSString.CompareOptions = []
        if !matchCase { opts.insert(.caseInsensitive) }
        if useRegex || wholeWord { opts.insert(.regularExpression) }
        return opts
    }

    // MARK: Find & Replace Bar

    private var findBar: some View {
        VStack(spacing: 6) {
            // Row 1: Search field + navigation
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Buscar…", text: $findText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(maxWidth: 300)
                    .focused($findFieldFocused)
                    .onSubmit { performFind(forward: true) }

                Text("\(matchCount) coincidencias")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 110, alignment: .leading)

                Button(action: { performFind(forward: false) }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: { performFind(forward: true) }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: { showFind = false; showReplace = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }

            // Row 2: Search options as checkboxes
            HStack(spacing: 16) {
                Toggle("Distinguir mayúsculas", isOn: $matchCase)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Toggle("Palabra completa", isOn: $wholeWord)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Toggle("Expresión regular", isOn: $useRegex)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                if let err = regexError, useRegex {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 10))
                        Text("Regex inválida: \(err)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()
            }

            // Row 3: Replace (optional)
            if showReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField("Reemplazar con…", text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .frame(maxWidth: 300)

                    Button("Reemplazar") { performReplace() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Button("Reemplazar todo") { performReplaceAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear { findFieldFocused = true }
        .onChange(of: showFind) { visible in if visible { findFieldFocused = true } }
        .onChange(of: findText) { _ in countMatches() }
        .onChange(of: tab.text) { _ in countMatches() }
        .onChange(of: matchCase) { _ in countMatches() }
        .onChange(of: wholeWord) { _ in countMatches() }
        .onChange(of: useRegex) { _ in countMatches() }
    }

    private func countMatches() {
        guard !findText.isEmpty else { matchCount = 0; regexError = nil; return }
        let pattern = buildSearchPattern()
        if regexError != nil { matchCount = 0; return }

        let text = tab.text as NSString
        let opts = effectiveOptions
        var count = 0
        var searchStart = 0
        while searchStart < text.length {
            let range = NSRange(location: searchStart, length: text.length - searchStart)
            let found = text.range(of: pattern, options: opts, range: range)
            if found.location == NSNotFound { break }
            count += 1
            searchStart = found.location + max(found.length, 1)
        }
        matchCount = count
    }

    private func performFind(forward: Bool) {
        guard !findText.isEmpty, let tv = tvRef.textView else { return }
        let pattern = buildSearchPattern()
        if regexError != nil { return }

        let text = tv.string as NSString
        let currentLoc = tv.selectedRange().location + (forward ? tv.selectedRange().length : 0)
        let opts = effectiveOptions

        if forward {
            let searchRange = NSRange(location: currentLoc, length: text.length - currentLoc)
            let found = text.range(of: pattern, options: opts, range: searchRange)
            if found.location != NSNotFound {
                tv.setSelectedRange(found)
                tv.scrollRangeToVisible(found)
            } else {
                // Wrap around
                let wrapRange = NSRange(location: 0, length: text.length)
                let wrapped = text.range(of: pattern, options: opts, range: wrapRange)
                if wrapped.location != NSNotFound {
                    tv.setSelectedRange(wrapped)
                    tv.scrollRangeToVisible(wrapped)
                }
            }
        } else {
            var backOpts = opts
            backOpts.insert(.backwards)
            let bRange = NSRange(location: 0, length: min(currentLoc, text.length))
            let found = text.range(of: pattern, options: backOpts, range: bRange)
            if found.location != NSNotFound {
                tv.setSelectedRange(found)
                tv.scrollRangeToVisible(found)
            } else {
                // Wrap around backwards
                let wrapRange = NSRange(location: 0, length: text.length)
                let wrapped = text.range(of: pattern, options: backOpts, range: wrapRange)
                if wrapped.location != NSNotFound {
                    tv.setSelectedRange(wrapped)
                    tv.scrollRangeToVisible(wrapped)
                }
            }
        }
        // Keep focus on the text view so subsequent arrow clicks work
        tv.window?.makeFirstResponder(tv)
    }

    private func performReplace() {
        guard !findText.isEmpty, let tv = tvRef.textView else { return }
        let pattern = buildSearchPattern()
        if regexError != nil { return }

        let sel = tv.selectedRange()
        let selectedText = (tv.string as NSString).substring(with: sel)
        let opts = effectiveOptions
        let match = (selectedText as NSString).range(of: pattern, options: opts,
                                                      range: NSRange(location: 0, length: (selectedText as NSString).length))
        if match.location == 0 && match.length == sel.length {
            if useRegex, let regex = try? NSRegularExpression(pattern: pattern,
                options: matchCase ? [] : [.caseInsensitive]) {
                let replaced = regex.stringByReplacingMatches(in: selectedText,
                    range: NSRange(location: 0, length: (selectedText as NSString).length),
                    withTemplate: replaceText)
                tv.insertText(replaced, replacementRange: sel)
            } else {
                tv.insertText(replaceText, replacementRange: sel)
            }
            tab.text = tv.string
            tab.isModified = true
        }
        performFind(forward: true)
    }

    private func performReplaceAll() {
        guard !findText.isEmpty else { return }
        let pattern = buildSearchPattern()
        if regexError != nil { return }

        let opts = effectiveOptions
        let result = (tab.text as NSString).replacingOccurrences(of: pattern, with: replaceText, options: opts,
                                                                  range: NSRange(location: 0, length: (tab.text as NSString).length))
        tab.text = result
        tab.isModified = true
        countMatches()
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Editor Code Area (NSViewRepresentable with cursor tracking)
// ═══════════════════════════════════════════════════════════════

struct EditorCodeArea: NSViewRepresentable {
    @ObservedObject var tab: EditorTab
    @ObservedObject var tvRef: EditorTextViewRef

    func makeNSView(context: Context) -> CodeScrollView {
        let sv = CodeScrollView(frame: .zero)
        sv.codeTextView.delegate = context.coordinator
        sv.codeTextView.isEditable = true
        sv.codeTextView.allowsUndo = true
        sv.enableLineNumbers()
        tvRef.textView = sv.codeTextView
        return sv
    }

    func updateNSView(_ sv: CodeScrollView, context: Context) {
        let tv = sv.codeTextView!
        guard !context.coordinator.isEditing else { return }

        let textChanged = tv.string != tab.text
        let langChanged = context.coordinator.lastLang != tab.language
        let wrapChanged = context.coordinator.lastWrap != tab.wordWrap

        if textChanged {
            let sel = tv.selectedRange()
            tv.string = tab.text
            let len = (tv.string as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }

        if textChanged || langChanged {
            SyntaxHighlighter.shared.apply(to: tv, language: tab.language)
            context.coordinator.lastLang = tab.language
            sv.lineRuler?.needsDisplay = true
        }

        if wrapChanged {
            if tab.wordWrap {
                tv.textContainer?.widthTracksTextView = true
                tv.isHorizontallyResizable = false
                sv.hasHorizontalScroller = false
                tv.textContainer?.size = NSSize(width: sv.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            } else {
                tv.textContainer?.widthTracksTextView = false
                tv.isHorizontallyResizable = true
                sv.hasHorizontalScroller = true
                tv.textContainer?.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
            context.coordinator.lastWrap = tab.wordWrap
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(tab: tab) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var tab: EditorTab
        var isEditing = false
        var lastLang: CodeLanguage = .none
        var lastWrap: Bool = true

        init(tab: EditorTab) { self.tab = tab }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            tab.text = tv.string
            tab.isModified = true
            SyntaxHighlighter.shared.apply(to: tv, language: tab.language)
            (tv.enclosingScrollView as? CodeScrollView)?.lineRuler?.needsDisplay = true
            DispatchQueue.main.async { self.isEditing = false }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            (tv.enclosingScrollView as? CodeScrollView)?.lineRuler?.needsDisplay = true
            updateCursorPosition(tv)
        }

        private func updateCursorPosition(_ tv: NSTextView) {
            let loc = tv.selectedRange().location
            let text = tv.string as NSString
            guard loc <= text.length else { return }

            var line = 1
            var col = 1
            let end = min(loc, text.length)
            for i in 0..<end {
                if text.character(at: i) == 0x0A { // \n
                    line += 1
                    col = 1
                } else {
                    col += 1
                }
            }
            tab.cursorLine = line
            tab.cursorColumn = col
        }
    }
}
