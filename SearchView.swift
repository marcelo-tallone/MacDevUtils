import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════
// MARK: - Search Types
// ═══════════════════════════════════════════════════════════════

enum SearchMode: String, CaseIterable {
    case content  = "Buscar en contenido"
    case fileName = "Buscar por nombre"
}

struct SearchMatch: Identifiable {
    let id = UUID()
    let filePath: String
    let fileName: String
    let lineNumber: Int?      // nil for file name searches
    let lineText: String?     // the matching line content
    let contextBefore: String? // line before match
    let contextAfter: String?  // line after match
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Search Engine
// ═══════════════════════════════════════════════════════════════

final class SearchEngine: ObservableObject {
    @Published var results: [SearchMatch] = []
    @Published var isSearching = false
    @Published var filesScanned = 0
    @Published var statusMessage = ""

    private var shouldCancel = false

    // Max file size to read (10 MB)
    private let maxFileSize: UInt64 = 10 * 1024 * 1024

    // Binary file extensions to skip
    private let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "ico", "icns",
        "mp3", "mp4", "avi", "mov", "mkv", "wav", "flac",
        "zip", "gz", "tar", "rar", "7z", "dmg", "iso",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "exe", "dll", "dylib", "so", "o", "a", "class",
        "app", "framework", "bundle",
    ]

    func cancel() {
        shouldCancel = true
    }

    func searchContent(query: String, rootPath: String, fileFilter: String,
                       matchCase: Bool, wholeWord: Bool, useRegex: Bool) {
        reset()
        isSearching = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let root = URL(fileURLWithPath: rootPath)
            let filterExts = self.parseFileFilter(fileFilter)
            var matches: [SearchMatch] = []
            var scanned = 0

            // Build regex/search pattern
            let pattern: String
            if useRegex {
                pattern = query
            } else if wholeWord {
                pattern = "\\b" + NSRegularExpression.escapedPattern(for: query) + "\\b"
            } else {
                pattern = NSRegularExpression.escapedPattern(for: query)
            }

            let regexOpts: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOpts) else {
                DispatchQueue.main.async {
                    self.statusMessage = "Patrón de búsqueda inválido"
                    self.isSearching = false
                }
                return
            }

            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                while let url = enumerator.nextObject() as? URL {
                    if self.shouldCancel { break }

                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                          values.isRegularFile == true else { continue }

                    // Check file size
                    if let size = values.fileSize, UInt64(size) > self.maxFileSize { continue }

                    // Check extension filter
                    let ext = url.pathExtension.lowercased()
                    if self.binaryExtensions.contains(ext) { continue }
                    if !filterExts.isEmpty && !filterExts.contains(ext) { continue }

                    // Read file
                    guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                    scanned += 1

                    if scanned % 100 == 0 {
                        DispatchQueue.main.async { self.filesScanned = scanned }
                    }

                    let lines = content.components(separatedBy: "\n")
                    for (idx, line) in lines.enumerated() {
                        let nsLine = line as NSString
                        let range = NSRange(location: 0, length: nsLine.length)
                        if regex.firstMatch(in: line, range: range) != nil {
                            let before = idx > 0 ? lines[idx - 1] : nil
                            let after = idx < lines.count - 1 ? lines[idx + 1] : nil
                            matches.append(SearchMatch(
                                filePath: url.path,
                                fileName: url.lastPathComponent,
                                lineNumber: idx + 1,
                                lineText: line.trimmingCharacters(in: .whitespaces),
                                contextBefore: before?.trimmingCharacters(in: .whitespaces),
                                contextAfter: after?.trimmingCharacters(in: .whitespaces)
                            ))
                            // Limit results to prevent memory issues
                            if matches.count >= 5000 { break }
                        }
                    }
                    if matches.count >= 5000 { break }
                }
            }

            DispatchQueue.main.async {
                self.results = matches
                self.filesScanned = scanned
                self.statusMessage = self.shouldCancel ? "Búsqueda cancelada" :
                    "\(matches.count) coincidencias en \(scanned) archivos"
                if matches.count >= 5000 {
                    self.statusMessage += " (límite alcanzado)"
                }
                self.isSearching = false
            }
        }
    }

    func searchFileName(query: String, rootPath: String, fileFilter: String,
                        matchCase: Bool, useRegex: Bool) {
        reset()
        isSearching = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let root = URL(fileURLWithPath: rootPath)
            let filterExts = self.parseFileFilter(fileFilter)
            var matches: [SearchMatch] = []
            var scanned = 0

            let pattern: String
            if useRegex {
                pattern = query
            } else {
                // Convert glob-like wildcards to regex
                var p = NSRegularExpression.escapedPattern(for: query)
                p = p.replacingOccurrences(of: "\\*", with: ".*")
                p = p.replacingOccurrences(of: "\\?", with: ".")
                pattern = p
            }

            let regexOpts: NSRegularExpression.Options = matchCase ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOpts) else {
                DispatchQueue.main.async {
                    self.statusMessage = "Patrón de búsqueda inválido"
                    self.isSearching = false
                }
                return
            }

            if let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                while let url = enumerator.nextObject() as? URL {
                    if self.shouldCancel { break }

                    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                          values.isRegularFile == true else { continue }

                    let ext = url.pathExtension.lowercased()
                    if !filterExts.isEmpty && !filterExts.contains(ext) { continue }

                    scanned += 1
                    if scanned % 500 == 0 {
                        DispatchQueue.main.async { self.filesScanned = scanned }
                    }

                    let name = url.lastPathComponent
                    let nsName = name as NSString
                    let range = NSRange(location: 0, length: nsName.length)
                    if regex.firstMatch(in: name, range: range) != nil {
                        matches.append(SearchMatch(
                            filePath: url.path,
                            fileName: name,
                            lineNumber: nil,
                            lineText: nil,
                            contextBefore: nil,
                            contextAfter: nil
                        ))
                        if matches.count >= 5000 { break }
                    }
                }
            }

            DispatchQueue.main.async {
                self.results = matches
                self.filesScanned = scanned
                self.statusMessage = self.shouldCancel ? "Búsqueda cancelada" :
                    "\(matches.count) archivos encontrados (de \(scanned) analizados)"
                if matches.count >= 5000 {
                    self.statusMessage += " (límite alcanzado)"
                }
                self.isSearching = false
            }
        }
    }

    private func reset() {
        shouldCancel = false
        results = []
        filesScanned = 0
        statusMessage = ""
    }

    private func parseFileFilter(_ filter: String) -> Set<String> {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        // Accept formats like: "*.json, *.xml" or "json xml" or ".json .xml"
        let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",; "))
        var exts: Set<String> = []
        for part in parts {
            var p = part.trimmingCharacters(in: .whitespaces)
            if p.isEmpty { continue }
            p = p.replacingOccurrences(of: "*.", with: "")
            if p.hasPrefix(".") { p = String(p.dropFirst()) }
            exts.insert(p.lowercased())
        }
        return exts
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Search View
// ═══════════════════════════════════════════════════════════════

struct SearchView: View {
    @StateObject private var engine = SearchEngine()
    @State private var searchQuery = ""
    @State private var searchMode: SearchMode = .content
    @State private var rootPath = ""
    @State private var fileFilter = ""
    @State private var matchCase = false
    @State private var wholeWord = false
    @State private var useRegex = false
    @State private var selectedResult: SearchMatch? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchForm
            Divider()
            resultsView
            Divider()
            statusBar
        }
    }

    // MARK: - Search Form

    private var searchForm: some View {
        VStack(spacing: 8) {
            // Row 1: search query
            HStack(spacing: 8) {
                Picker("", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 180)

                TextField("Texto a buscar…", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { startSearch() }

                if engine.isSearching {
                    Button(action: engine.cancel) {
                        Label("Cancelar", systemImage: "xmark.circle")
                    }
                    .foregroundColor(.red)
                } else {
                    Button(action: startSearch) {
                        Label("Buscar", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchQuery.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }

            // Row 2: root path + file filter
            HStack(spacing: 8) {
                Text("Directorio:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextField("/ (toda la Mac)", text: $rootPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                Button(action: chooseDirectory) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider().frame(height: 18)

                Text("Filtro:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextField("ej: *.json, *.xml", text: $fileFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 160)
            }

            // Row 3: options
            HStack(spacing: 16) {
                Toggle("Distinguir mayúsculas", isOn: $matchCase)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                if searchMode == .content {
                    Toggle("Palabra completa", isOn: $wholeWord)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }

                Toggle("Expresión regular", isOn: $useRegex)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Spacer()

                if engine.isSearching {
                    ProgressView()
                        .controlSize(.small)
                    Text("Buscando… \(engine.filesScanned) archivos")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Results View

    private var resultsView: some View {
        Group {
            if engine.results.isEmpty && !engine.isSearching && !engine.statusMessage.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Sin resultados")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text(engine.statusMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if engine.results.isEmpty && engine.statusMessage.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Buscador de archivos")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Buscá por contenido o por nombre de archivo")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(engine.results) { match in
                    resultRow(match)
                        .onTapGesture(count: 2) { openInEditor(match) }
                        .onTapGesture { selectedResult = match }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func resultRow(_ match: SearchMatch) -> some View {
        let isSelected = selectedResult?.id == match.id

        return VStack(alignment: .leading, spacing: 2) {
            // File path + line number
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)

                Text(match.fileName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)

                if let ln = match.lineNumber {
                    Text(":\(ln)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.orange)
                }

                Spacer()

                Text(shortenPath(match.filePath))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Content match with context
            if let lineText = match.lineText {
                VStack(alignment: .leading, spacing: 1) {
                    if let before = match.contextBefore, !before.isEmpty {
                        Text(before)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    }

                    Text(lineText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(NSColor.labelColor))
                        .lineLimit(2)

                    if let after = match.contextAfter, !after.isEmpty {
                        Text(after)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(engine.statusMessage.isEmpty ? "Listo" : engine.statusMessage)
                .font(.system(size: 11))

            Spacer()

            if selectedResult != nil {
                Text("Doble click para abrir en el Editor")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .foregroundColor(.secondary)
    }

    // MARK: - Actions

    private func startSearch() {
        guard !searchQuery.isEmpty else { return }
        let root = rootPath.trimmingCharacters(in: .whitespaces)
        let effectiveRoot = root.isEmpty ? "/" : root

        switch searchMode {
        case .content:
            engine.searchContent(query: searchQuery, rootPath: effectiveRoot,
                                 fileFilter: fileFilter, matchCase: matchCase,
                                 wholeWord: wholeWord, useRegex: useRegex)
        case .fileName:
            engine.searchFileName(query: searchQuery, rootPath: effectiveRoot,
                                  fileFilter: fileFilter, matchCase: matchCase,
                                  useRegex: useRegex)
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
        }
    }

    private func openInEditor(_ match: SearchMatch) {
        let url = URL(fileURLWithPath: match.filePath)
        NotificationCenter.default.post(name: .openFileFromFinder, object: url)
    }
}
