import SwiftUI
import AppKit

// MARK: - Shared Types

enum Tool: String, CaseIterable {
    case converter = "Conversor"
    case editor    = "Editor"
    case validator = "Validador"
    case compare   = "Comparar"
    case search    = "Buscador"

    var icon: String {
        switch self {
        case .converter: return "arrow.left.arrow.right"
        case .editor:    return "doc.text"
        case .validator: return "checkmark.shield"
        case .compare:   return "doc.on.doc"
        case .search:    return "magnifyingglass"
        }
    }

    var subtitle: String {
        switch self {
        case .converter: return "Convertir entre formatos"
        case .editor:    return "Editor de documentos"
        case .validator: return "Validar y formatear"
        case .compare:   return "Comparar textos"
        case .search:    return "Buscar en archivos"
        }
    }
}

enum CodeLanguage: String, CaseIterable {
    case none = "Texto plano"
    case json = "JSON"
    case xml  = "XML"
    case html = "HTML"
    case sql  = "SQL"
    case css  = "CSS"
}

enum DataFormat: String, CaseIterable, Identifiable {
    case ascii        = "ASCII"
    case hex          = "HEX"
    case base64       = "Base64"
    case binary       = "Binario"
    case decimal      = "Decimal"
    case urlEncoded   = "URL Encode"
    case htmlEntities = "HTML Entities"
    case utf8Bytes    = "UTF-8 Bytes"

    var id: String { rawValue }
}

enum ValidateFormat: String, CaseIterable, Identifiable {
    case json  = "JSON"
    case xml   = "XML"
    case html  = "HTML"
    case yaml  = "YAML"
    case sql   = "SQL"
    case hex   = "HEX"
    case ascii = "ASCII"
    case blob  = "BLOB"

    var id: String { rawValue }

    var codeLanguage: CodeLanguage {
        switch self {
        case .json:  return .json
        case .xml:   return .xml
        case .html:  return .html
        case .sql:   return .sql
        default:     return .none
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedTool: Tool = .converter

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selectedTool: $selectedTool)
            Divider()
            ZStack {
                ConverterView()
                    .opacity(selectedTool == .converter ? 1 : 0)
                    .allowsHitTesting(selectedTool == .converter)
                EditorView()
                    .opacity(selectedTool == .editor ? 1 : 0)
                    .allowsHitTesting(selectedTool == .editor)
                ValidatorView()
                    .opacity(selectedTool == .validator ? 1 : 0)
                    .allowsHitTesting(selectedTool == .validator)
                CompareView()
                    .opacity(selectedTool == .compare ? 1 : 0)
                    .allowsHitTesting(selectedTool == .compare)
                SearchView()
                    .opacity(selectedTool == .search ? 1 : 0)
                    .allowsHitTesting(selectedTool == .search)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileFromFinder)) { _ in
            selectedTool = .editor
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedTool: Tool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("MacDevUtils")
                    .font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().padding(.bottom, 6)

            ForEach(Tool.allCases, id: \.self) { tool in
                SidebarButton(tool: tool, isSelected: selectedTool == tool) {
                    selectedTool = tool
                }
            }

            Spacer()

            Text("v1.0")
                .font(.caption2)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 6)
        .frame(width: 200)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct SidebarButton: View {
    let tool: Tool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tool.icon)
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tool.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    Text(tool.subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// Placeholder for tools not yet built
struct PlaceholderView: View {
    let tool: Tool
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(tool.rawValue)
                .font(.title2)
            Text("Próximamente")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
