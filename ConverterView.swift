import SwiftUI
import Foundation

// ═══════════════════════════════════════════════════════════════
// MARK: - Conversion Logic
// ═══════════════════════════════════════════════════════════════

enum ConvertError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let m) = self { return m }; return nil
    }
}

struct DataConverter {

    static func convert(_ input: String, from src: DataFormat, to dst: DataFormat) -> Result<String, ConvertError> {
        guard let bytes = decode(input, format: src) else {
            return .failure(.invalid("Input inválido para \(src.rawValue)"))
        }
        return .success(encode(bytes, format: dst))
    }

    // ── Decode: format → Data ──────────────────────────────

    private static func decode(_ input: String, format: DataFormat) -> Data? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch format {

        case .ascii:
            return s.data(using: .isoLatin1) ?? s.data(using: .utf8)

        case .hex:
            let clean = s.replacingOccurrences(of: #"[\s:,]"#, with: "", options: .regularExpression)
            guard clean.count % 2 == 0 else { return nil }
            var bytes = [UInt8](); var i = clean.startIndex
            while i < clean.endIndex {
                let j = clean.index(i, offsetBy: 2)
                guard let b = UInt8(clean[i..<j], radix: 16) else { return nil }
                bytes.append(b); i = j
            }
            return Data(bytes)

        case .base64:
            return Data(base64Encoded: s, options: .ignoreUnknownCharacters)

        case .binary:
            let clean = s.replacingOccurrences(of: #"[\s]"#, with: "", options: .regularExpression)
            guard !clean.isEmpty, clean.count % 8 == 0,
                  clean.allSatisfy({ $0 == "0" || $0 == "1" }) else { return nil }
            var bytes = [UInt8](); var i = clean.startIndex
            while i < clean.endIndex {
                let j = clean.index(i, offsetBy: 8)
                bytes.append(UInt8(clean[i..<j], radix: 2)!); i = j
            }
            return Data(bytes)

        case .decimal:
            let parts = s.components(separatedBy: CharacterSet(charactersIn: " ,\t\n")).filter { !$0.isEmpty }
            let bytes = parts.compactMap { UInt8($0) }
            guard bytes.count == parts.count else { return nil }
            return Data(bytes)

        case .urlEncoded:
            guard let decoded = s.removingPercentEncoding else { return nil }
            return decoded.data(using: .utf8)

        case .htmlEntities:
            return htmlDecode(s).data(using: .utf8)

        case .utf8Bytes:
            let parts = s.components(separatedBy: CharacterSet(charactersIn: " ,\t\n")).filter { !$0.isEmpty }
            let bytes = parts.compactMap { UInt8($0) }
            guard bytes.count == parts.count else { return nil }
            return Data(bytes)
        }
    }

    // ── Encode: Data → format ──────────────────────────────

    private static func encode(_ data: Data, format: DataFormat) -> String {
        switch format {

        case .ascii:
            return String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .utf8)
                ?? "(no representable)"

        case .hex:
            return data.map { String(format: "%02X", $0) }.joined(separator: " ")

        case .base64:
            return data.base64EncodedString(options: .lineLength64Characters)

        case .binary:
            return data.map { pad(String($0, radix: 2), 8) }.joined(separator: " ")

        case .decimal:
            return data.map { String($0) }.joined(separator: " ")

        case .urlEncoded:
            let str = String(data: data, encoding: .utf8) ?? ""
            return str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? str

        case .htmlEntities:
            let str = String(data: data, encoding: .utf8) ?? ""
            return htmlEncode(str)

        case .utf8Bytes:
            return data.map { String($0) }.joined(separator: " ")
        }
    }

    // ── HTML entity helpers ────────────────────────────────

    private static func htmlDecode(_ s: String) -> String {
        var r = s
        for (entity, ch) in [("&amp;","&"),("&lt;","<"),("&gt;",">"),
                              ("&quot;","\""),("&apos;","'"),("&nbsp;"," ")] {
            r = r.replacingOccurrences(of: entity, with: ch)
        }
        // Numeric: &#NNN; / &#xHH;
        if let rx = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let ns = r as NSString
            for m in rx.matches(in: r, range: NSRange(0..<ns.length)).reversed() {
                let hex = ns.substring(with: m.range(at: 1))
                if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                    r = ns.replacingCharacters(in: m.range, with: String(scalar))
                }
            }
        }
        if let rx = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = r as NSString
            for m in rx.matches(in: r, range: NSRange(0..<ns.length)).reversed() {
                let dec = ns.substring(with: m.range(at: 1))
                if let code = UInt32(dec), let scalar = Unicode.Scalar(code) {
                    r = ns.replacingCharacters(in: m.range, with: String(scalar))
                }
            }
        }
        return r
    }

    private static func htmlEncode(_ s: String) -> String {
        s.unicodeScalars.map { sc -> String in
            switch sc.value {
            case 38:    return "&amp;"
            case 60:    return "&lt;"
            case 62:    return "&gt;"
            case 34:    return "&quot;"
            case 39:    return "&apos;"
            case 128...: return "&#\(sc.value);"
            default:    return String(sc)
            }
        }.joined()
    }

    private static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? s : String(repeating: "0", count: n - s.count) + s
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Converter View
// ═══════════════════════════════════════════════════════════════

struct ConverterView: View {
    @State private var inputText  = ""
    @State private var outputText = ""
    @State private var fromFmt    = DataFormat.ascii
    @State private var toFmt      = DataFormat.hex
    @State private var errorMsg   = ""
    @State private var hasError   = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            splitPanels
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Label("De:", systemImage: "arrow.right.circle")
                .foregroundColor(.secondary).font(.callout)

            Picker("", selection: $fromFmt) {
                ForEach(DataFormat.allCases) { f in Text(f.rawValue).tag(f) }
            }.frame(width: 140)

            Image(systemName: "arrow.right").foregroundColor(.secondary)

            Picker("", selection: $toFmt) {
                ForEach(DataFormat.allCases) { f in Text(f.rawValue).tag(f) }
            }.frame(width: 140)

            Button(action: convert) {
                Label("Convertir", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)

            Button(action: swapFormats) {
                Image(systemName: "arrow.left.arrow.right")
            }.help("Intercambiar formatos e input/output")

            Button(action: clear) {
                Image(systemName: "trash")
            }.help("Limpiar todo")

            Spacer()

            if hasError {
                Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red).font(.callout)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: Split panels

    private var splitPanels: some View {
        HSplitView {
            VStack(spacing: 0) {
                panelHeader("Input — \(fromFmt.rawValue)")
                CodeEditor(text: $inputText, language: .none, showLineNumbers: true)
            }
            VStack(spacing: 0) {
                panelHeader("Output — \(toFmt.rawValue)")
                CodeEditor(text: $outputText, language: .none, isEditable: false, showLineNumbers: true)
            }
        }
    }

    @ViewBuilder
    private func panelHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor))
        Divider()
    }

    // MARK: Actions

    private func convert() {
        hasError = false
        switch DataConverter.convert(inputText, from: fromFmt, to: toFmt) {
        case .success(let out):
            outputText = out
        case .failure(let err):
            hasError = true
            errorMsg = err.localizedDescription
            outputText = ""
        }
    }

    private func swapFormats() {
        let tmp = fromFmt; fromFmt = toFmt; toFmt = tmp
        if !outputText.isEmpty { inputText = outputText; outputText = "" }
    }

    private func clear() {
        inputText = ""; outputText = ""; hasError = false; errorMsg = ""
    }
}
