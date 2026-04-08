import SwiftUI
import Foundation

// ═══════════════════════════════════════════════════════════════
// MARK: - Validation Types
// ═══════════════════════════════════════════════════════════════

struct ValidationError: Identifiable {
    let id = UUID()
    let line: Int
    let column: Int?
    let message: String
}

struct ValidationResult {
    let formatted: String?
    let errors: [ValidationError]
    var isValid: Bool { errors.isEmpty }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Validator Logic
// ═══════════════════════════════════════════════════════════════

struct Validator {

    static func validate(_ input: String, as fmt: ValidateFormat) -> ValidationResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ValidationResult(formatted: nil, errors: [
                ValidationError(line: 1, column: nil, message: "El input está vacío")
            ])
        }
        switch fmt {
        case .json:  return validateJSON(input)
        case .xml:   return validateXML(input)
        case .html:  return validateHTML(input)
        case .yaml:  return validateYAML(input)
        case .sql:   return validateSQL(input)
        case .hex:   return validateHEX(input)
        case .ascii: return validateASCII(input)
        case .blob:  return validateBLOB(input)
        }
    }

    // ── JSON ───────────────────────────────────────────────

    private static func validateJSON(_ input: String) -> ValidationResult {
        // Normalize line endings for consistent line counting
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // First: run our own parser for precise error reporting
        let linter = JSONLinter(normalized)
        let lintErrors = linter.validate()

        if !lintErrors.isEmpty {
            return ValidationResult(formatted: nil, errors: lintErrors)
        }

        // Use our own formatter that preserves key order
        let formatted = JSONPrettyPrinter.format(normalized)
        return ValidationResult(formatted: formatted, errors: [])
    }

    // ── JSON Pretty Printer (preserves key order) ─────────

    private final class JSONPrettyPrinter {
        private let chars: [Character]
        private var pos = 0
        private var output = ""
        private var indent = 0
        private let tab = "  "

        static func format(_ input: String) -> String {
            let p = JSONPrettyPrinter(input)
            p.skipWS()
            p.writeValue()
            return p.output
        }

        private init(_ input: String) { chars = Array(input) }

        private var atEnd: Bool { pos >= chars.count }
        private var cur: Character { chars[pos] }
        @discardableResult private func eat() -> Character { let c = chars[pos]; pos += 1; return c }
        private func skipWS() { while !atEnd && cur.isWhitespace { pos += 1 } }

        private func newline() { output += "\n"; for _ in 0..<indent { output += tab } }

        private func writeValue() {
            guard !atEnd else { return }
            switch cur {
            case "\"": writeString()
            case "{":  writeObject()
            case "[":  writeArray()
            case "t", "f", "n": writeLiteral()
            default:   writeNumber()
            }
        }

        private func writeString() {
            output.append(eat()) // opening "
            while !atEnd {
                let c = eat()
                output.append(c)
                if c == "\\" && !atEnd { output.append(eat()) } // escape sequence
                else if c == "\"" { return }
            }
        }

        private func writeObject() {
            eat() // {
            skipWS()
            if !atEnd && cur == "}" { eat(); output += "{}"; return }

            output += "{"
            indent += 1
            var first = true

            while !atEnd {
                skipWS()
                if cur == "}" { break }

                // consume comma between entries
                if !first {
                    if cur == "," { eat(); skipWS() }
                    output += ","
                }
                first = false

                newline()

                // key
                writeString()
                skipWS()

                // colon
                eat() // :
                output += ": "
                skipWS()

                // value
                writeValue()
            }

            indent -= 1
            newline()
            output += "}"
            if !atEnd && cur == "}" { eat() } else { /* already consumed */ }
        }

        private func writeArray() {
            eat() // [
            skipWS()
            if !atEnd && cur == "]" { eat(); output += "[]"; return }

            output += "["
            indent += 1
            var first = true

            while !atEnd {
                skipWS()
                if cur == "]" { break }

                if !first {
                    if cur == "," { eat(); skipWS() }
                    output += ","
                }
                first = false

                newline()
                writeValue()
            }

            indent -= 1
            newline()
            output += "]"
            if !atEnd && cur == "]" { eat() } else { /* already consumed */ }
        }

        private func writeNumber() {
            while !atEnd {
                let c = cur
                if c == "," || c == "}" || c == "]" || c.isWhitespace { break }
                output.append(eat())
            }
        }

        private func writeLiteral() {
            while !atEnd && cur.isLetter { output.append(eat()) }
        }
    }

    // ── JSON Linter (character-level parser for precise errors) ──

    private final class JSONLinter {
        private let chars: [Character]
        private let input: String
        private var pos = 0
        private var line = 1
        private var col = 1
        private var errors: [ValidationError] = []

        init(_ input: String) {
            // Normalize line endings: \r\n → \n, solo \r → \n
            let normalized = input
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            self.input = normalized
            self.chars = Array(normalized)
        }

        func validate() -> [ValidationError] {
            skipWhitespace()
            if atEnd() {
                addError("JSON vacío")
                return errors
            }
            parseValue()
            skipWhitespace()
            if !atEnd() {
                addError("Contenido inesperado después del valor JSON: '\(currentSnippet())'")
            }
            return errors
        }

        // MARK: Parsing

        private func parseValue() {
            guard !atEnd() else { addError("Se esperaba un valor, pero el input terminó"); return }
            switch peek() {
            case "{":  parseObject()
            case "[":  parseArray()
            case "\"": parseString()
            case "t":  parseLiteral("true",  "true")
            case "f":  parseLiteral("false", "false")
            case "n":  parseLiteral("null",  "null")
            case let c where c == "-" || c.isNumber: parseNumber()
            default:
                addError("Carácter inesperado '\(peek())' — se esperaba un valor (string, número, objeto, array, true, false o null)")
                advance()
            }
        }

        private func parseObject() {
            let startLine = line; let startCol = col
            consume("{")
            skipWhitespace()

            if !atEnd() && peek() == "}" { advance(); return }

            var expectingComma = false
            while !atEnd() {
                skipWhitespace()
                if atEnd() {
                    addError("Objeto abierto en línea \(startLine), col \(startCol) — falta '}'")
                    return
                }

                if expectingComma {
                    if peek() == "}" { advance(); return }
                    if peek() != "," {
                        addError("Se esperaba ',' o '}' después de un valor en el objeto")
                        return
                    }
                    advance() // consume ','
                    skipWhitespace()
                    if !atEnd() && peek() == "}" {
                        addError("Coma extra antes de '}'")
                        advance()
                        return
                    }
                }

                skipWhitespace()
                guard !atEnd() else {
                    addError("Se esperaba una clave (string) pero el input terminó")
                    return
                }

                // Key
                if peek() != "\"" {
                    addError("Se esperaba una clave entre comillas (\"), encontré '\(peek())'")
                    return
                }
                parseString()

                // Colon
                skipWhitespace()
                guard !atEnd() else { addError("Se esperaba ':' después de la clave, pero el input terminó"); return }
                if peek() != ":" {
                    addError("Se esperaba ':' después de la clave, encontré '\(peek())'")
                    return
                }
                advance()

                // Value
                skipWhitespace()
                parseValue()
                if !errors.isEmpty { return }

                expectingComma = true
            }
            addError("Objeto abierto en línea \(startLine), col \(startCol) — falta '}'")
        }

        private func parseArray() {
            let startLine = line; let startCol = col
            consume("[")
            skipWhitespace()

            if !atEnd() && peek() == "]" { advance(); return }

            var expectingComma = false
            while !atEnd() {
                skipWhitespace()
                if atEnd() {
                    addError("Array abierto en línea \(startLine), col \(startCol) — falta ']'")
                    return
                }

                if expectingComma {
                    if peek() == "]" { advance(); return }
                    if peek() != "," {
                        addError("Se esperaba ',' o ']' después de un valor en el array")
                        return
                    }
                    advance()
                    skipWhitespace()
                    if !atEnd() && peek() == "]" {
                        addError("Coma extra antes de ']'")
                        advance()
                        return
                    }
                }

                skipWhitespace()
                parseValue()
                if !errors.isEmpty { return }

                expectingComma = true
            }
            addError("Array abierto en línea \(startLine), col \(startCol) — falta ']'")
        }

        private func parseString() {
            let startLine = line; let startCol = col
            guard !atEnd() && peek() == "\"" else { addError("Se esperaba un string (comilla de apertura)"); return }
            advance() // opening "

            while !atEnd() {
                let c = peek()
                if c == "\\" {
                    advance() // backslash
                    if atEnd() { addError("String sin cerrar — backslash al final"); return }
                    let escaped = peek()
                    if !"\"\\bfnrtu/".contains(escaped) {
                        addError("Secuencia de escape inválida '\\(\(escaped))' en string")
                    }
                    advance()
                } else if c == "\"" {
                    advance() // closing "
                    return
                } else if c == "\n" {
                    addError("String sin cerrar (abierto en línea \(startLine), col \(startCol)) — salto de línea dentro del string")
                    return
                } else {
                    advance()
                }
            }
            addError("String sin cerrar (abierto en línea \(startLine), col \(startCol)) — falta comilla de cierre")
        }

        private func parseNumber() {
            if !atEnd() && peek() == "-" { advance() }
            guard !atEnd() && peek().isNumber else { addError("Se esperaba un dígito en el número"); return }

            if peek() == "0" {
                advance()
                if !atEnd() && peek().isNumber {
                    addError("Número no puede tener ceros a la izquierda")
                    return
                }
            } else {
                consumeDigits()
            }

            // Fraction
            if !atEnd() && peek() == "." {
                advance()
                guard !atEnd() && peek().isNumber else { addError("Se esperaba un dígito después del punto decimal"); return }
                consumeDigits()
            }

            // Exponent
            if !atEnd() && (peek() == "e" || peek() == "E") {
                advance()
                if !atEnd() && (peek() == "+" || peek() == "-") { advance() }
                guard !atEnd() && peek().isNumber else { addError("Se esperaba un dígito en el exponente"); return }
                consumeDigits()
            }
        }

        private func parseLiteral(_ expected: String, _ name: String) {
            let startLine = line; let startCol = col
            for ch in expected {
                guard !atEnd() else {
                    addError("Literal '\(name)' incompleto (empezado en línea \(startLine), col \(startCol))")
                    return
                }
                if peek() != ch {
                    addError("Se esperaba '\(name)', encontré '\(currentSnippet())'")
                    return
                }
                advance()
            }
        }

        // MARK: Helpers

        private func atEnd() -> Bool { pos >= chars.count }
        private func peek() -> Character { chars[pos] }

        private func advance() {
            if pos < chars.count {
                if chars[pos] == "\n" { line += 1; col = 1 } else { col += 1 }
                pos += 1
            }
        }

        private func consume(_ expected: Character) {
            if !atEnd() && peek() == expected { advance() }
        }

        private func consumeDigits() {
            while !atEnd() && peek().isNumber { advance() }
        }

        private func skipWhitespace() {
            while !atEnd() && peek().isWhitespace { advance() }
        }

        private func addError(_ msg: String) {
            if errors.count < 10 {
                errors.append(ValidationError(line: line, column: col, message: msg))
            }
        }

        private func currentSnippet() -> String {
            let end = min(pos + 10, chars.count)
            return String(chars[pos..<end])
        }
    }

    // ── XML ────────────────────────────────────────────────

    private static func validateXML(_ input: String) -> ValidationResult {
        guard let data = input.data(using: .utf8) else {
            return err(1, nil, "No se puede codificar como UTF-8")
        }
        do {
            let doc = try XMLDocument(data: data, options: [])
            let pretty = doc.xmlString(options: [.nodePrettyPrint])
            return ValidationResult(formatted: pretty, errors: [])
        } catch let e as NSError {
            let line = (e.userInfo["NSXMLParserErrorLineNumber"] as? Int) ?? 1
            let col  = e.userInfo["NSXMLParserErrorColumn"] as? Int
            return err(line, col, simplifyErrorMessage(e.localizedDescription))
        }
    }

    // ── HTML ───────────────────────────────────────────────

    private static func validateHTML(_ input: String) -> ValidationResult {
        guard let data = input.data(using: .utf8) else {
            return err(1, nil, "No se puede codificar como UTF-8")
        }
        do {
            let doc = try XMLDocument(data: data, options: [.documentTidyHTML])
            let pretty = doc.xmlString(options: [.nodePrettyPrint])
            return ValidationResult(formatted: pretty, errors: [])
        } catch let e as NSError {
            let line = (e.userInfo["NSXMLParserErrorLineNumber"] as? Int) ?? 1
            let col  = e.userInfo["NSXMLParserErrorColumn"] as? Int
            return err(line, col, simplifyErrorMessage(e.localizedDescription))
        }
    }

    // ── YAML (básico) ──────────────────────────────────────

    private static func validateYAML(_ input: String) -> ValidationResult {
        var errors: [ValidationError] = []
        let lines = input.components(separatedBy: "\n")
        var prevIndent = 0

        for (i, line) in lines.enumerated() {
            let lineNum = i + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // Check mixed tabs and spaces
            let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
            if leading.contains("\t") && leading.contains(" ") {
                errors.append(ValidationError(line: lineNum, column: 1,
                    message: "Mezcla de tabs y espacios en la indentación"))
            }

            // Check for key-value structure
            let indent = leading.count
            if indent > prevIndent + 4 {
                errors.append(ValidationError(line: lineNum, column: indent + 1,
                    message: "Salto de indentación mayor a 4 espacios"))
            }
            prevIndent = indent

            // Check unbalanced quotes
            let singleQuotes = trimmed.filter({ $0 == "'" }).count
            let doubleQuotes = trimmed.filter({ $0 == "\"" }).count
            if singleQuotes % 2 != 0 {
                errors.append(ValidationError(line: lineNum, column: nil,
                    message: "Comilla simple sin cerrar"))
            }
            if doubleQuotes % 2 != 0 {
                errors.append(ValidationError(line: lineNum, column: nil,
                    message: "Comilla doble sin cerrar"))
            }

            if errors.count >= 20 { break }
        }

        // Re-indent for pretty output
        let formatted = input // YAML passthrough — no built-in reformatter
        return ValidationResult(formatted: errors.isEmpty ? formatted : nil, errors: errors)
    }

    // ── SQL (básico) ───────────────────────────────────────

    private static func validateSQL(_ input: String) -> ValidationResult {
        var errors: [ValidationError] = []
        let lines = input.components(separatedBy: "\n")

        // Check balanced parentheses
        var parenDepth = 0
        for (i, line) in lines.enumerated() {
            let lineNum = i + 1
            for ch in line {
                if ch == "(" { parenDepth += 1 }
                if ch == ")" {
                    parenDepth -= 1
                    if parenDepth < 0 {
                        errors.append(ValidationError(line: lineNum, column: nil,
                            message: "Paréntesis de cierre sin apertura"))
                        parenDepth = 0
                    }
                }
            }

            // Check unclosed strings
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let quotes = trimmed.filter({ $0 == "'" }).count
            if quotes % 2 != 0 {
                errors.append(ValidationError(line: lineNum, column: nil,
                    message: "Comilla simple sin cerrar"))
            }

            if errors.count >= 20 { break }
        }

        if parenDepth > 0 {
            errors.append(ValidationError(line: lines.count, column: nil,
                message: "\(parenDepth) paréntesis sin cerrar"))
        }

        // Format SQL keywords uppercase, add newlines before major clauses
        let formatted = errors.isEmpty ? formatSQL(input) : nil
        return ValidationResult(formatted: formatted, errors: errors)
    }

    private static func formatSQL(_ input: String) -> String {
        let majorKeywords = ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES",
                             "UPDATE", "SET", "DELETE", "CREATE", "DROP", "ALTER",
                             "JOIN", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN", "OUTER JOIN",
                             "ON", "ORDER BY", "GROUP BY", "HAVING", "LIMIT", "UNION"]
        var result = input
        // Uppercase keywords
        for kw in majorKeywords {
            if let rx = try? NSRegularExpression(pattern: "\\b\(kw)\\b", options: .caseInsensitive) {
                let ns = result as NSString
                for m in rx.matches(in: result, range: NSRange(0..<ns.length)).reversed() {
                    result = ns.replacingCharacters(in: m.range, with: kw)
                }
            }
        }
        // Add newlines before major clauses
        for kw in ["SELECT", "FROM", "WHERE", "ORDER BY", "GROUP BY", "HAVING",
                    "LIMIT", "UNION", "INSERT", "VALUES", "SET"] {
            result = result.replacingOccurrences(of: " \(kw) ", with: "\n\(kw) ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ── HEX ────────────────────────────────────────────────

    private static func validateHEX(_ input: String) -> ValidationResult {
        let clean = input.replacingOccurrences(of: #"[\s:,]"#, with: "", options: .regularExpression)
        var errors: [ValidationError] = []

        if clean.count % 2 != 0 {
            errors.append(ValidationError(line: 1, column: nil,
                message: "Número impar de caracteres hex (\(clean.count))"))
        }

        var pos = 0
        for ch in input {
            pos += 1
            if ch.isWhitespace || ch == ":" || ch == "," { continue }
            if !ch.isHexDigit {
                let (l, c) = charToLineCol(pos - 1, in: input)
                errors.append(ValidationError(line: l, column: c,
                    message: "Carácter inválido: '\(ch)'"))
                if errors.count >= 10 { break }
            }
        }

        guard errors.isEmpty else { return ValidationResult(formatted: nil, errors: errors) }

        // Format: pairs, 16 per line with offset
        var formatted = ""; var count = 0; var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            formatted += clean[i..<j]; count += 1
            formatted += count % 16 == 0 ? "\n" : " "
            i = j
        }
        return ValidationResult(formatted: formatted.trimmingCharacters(in: .whitespacesAndNewlines), errors: [])
    }

    // ── ASCII ──────────────────────────────────────────────

    private static func validateASCII(_ input: String) -> ValidationResult {
        var errors: [ValidationError] = []
        var line = 1; var col = 1
        for ch in input {
            if ch == "\n" { line += 1; col = 1; continue }
            if ch.asciiValue == nil {
                let hex = ch.unicodeScalars.first.map { String(format: "U+%04X", $0.value) } ?? "?"
                errors.append(ValidationError(line: line, column: col,
                    message: "Carácter no-ASCII: '\(ch)' (\(hex))"))
                if errors.count >= 30 { break }
            }
            col += 1
        }
        return ValidationResult(formatted: errors.isEmpty ? input : nil, errors: errors)
    }

    // ── BLOB → hex dump ────────────────────────────────────

    private static func validateBLOB(_ input: String) -> ValidationResult {
        guard let data = input.data(using: .utf8) else {
            return err(1, nil, "No se puede codificar como UTF-8")
        }
        var out = ""
        var offset = 0
        while offset < data.count {
            let end   = min(offset + 16, data.count)
            let chunk = data[offset..<end]
            let hex   = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = chunk.map { b -> String in
                let c = Character(UnicodeScalar(b))
                return (b >= 0x20 && b < 0x7F) ? String(c) : "."
            }.joined()
            out += String(format: "%08X  %-47s  |%@|\n", offset, hex as NSString, ascii as NSString)
            offset += 16
        }
        return ValidationResult(formatted: out, errors: [])
    }

    // ── Helpers ────────────────────────────────────────────

    private static func err(_ line: Int, _ col: Int?, _ msg: String) -> ValidationResult {
        ValidationResult(formatted: nil, errors: [ValidationError(line: line, column: col, message: msg)])
    }

    static func charToLineCol(_ idx: Int, in text: String) -> (Int, Int) {
        var line = 1; var col = 1
        for (i, ch) in text.enumerated() {
            if i >= idx { break }
            if ch == "\n" { line += 1; col = 1 } else { col += 1 }
        }
        return (line, col)
    }

    private static func simplifyErrorMessage(_ msg: String) -> String {
        // Remove verbose "The operation couldn't be completed" prefix
        if let range = msg.range(of: "The operation couldn't be completed. ") {
            return String(msg[range.upperBound...])
        }
        return msg
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Validator View
// ═══════════════════════════════════════════════════════════════

struct ValidatorView: View {
    @State private var inputText  = ""
    @State private var outputText = ""
    @State private var format     = ValidateFormat.json
    @State private var errors: [ValidationError] = []
    @State private var isValid: Bool? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            splitPanels

            if !errors.isEmpty {
                Divider()
                errorPanel
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 14) {
            Label("Formato:", systemImage: "doc.badge.gearshape")
                .foregroundColor(.secondary).font(.callout)

            Picker("", selection: $format) {
                ForEach(ValidateFormat.allCases) { f in Text(f.rawValue).tag(f) }
            }.frame(width: 110)

            Button(action: validate) {
                Label("Validar y formatear", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)

            Button(action: clear) {
                Label("Limpiar", systemImage: "trash")
            }

            Spacer()

            if let valid = isValid {
                HStack(spacing: 4) {
                    Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(valid ? "Válido" : "\(errors.count) error(es)")
                }
                .font(.callout.bold())
                .foregroundColor(valid ? .green : .red)
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
                panelHeader("Input")
                CodeEditor(text: $inputText, language: format.codeLanguage, showLineNumbers: true,
                          errorLines: Set(errors.map { $0.line }))
            }

            VStack(spacing: 0) {
                panelHeader("Output formateado")
                CodeEditor(text: $outputText, language: format.codeLanguage, isEditable: false, showLineNumbers: true)
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

    // MARK: Error panel

    private var errorPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("\(errors.count) error(es) encontrado(s)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.red.opacity(0.07))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(errors) { error in
                        HStack(alignment: .top, spacing: 10) {
                            Text(lineLabel(error))
                                .font(.system(size: 11, design: .monospaced).bold())
                                .foregroundColor(.red)
                                .frame(width: 90, alignment: .leading)
                                .textSelection(.enabled)

                            Text(error.message)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 4)

                        Divider().padding(.leading, 112)
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    private func lineLabel(_ e: ValidationError) -> String {
        var s = "Ln \(e.line)"
        if let c = e.column { s += ", Col \(c)" }
        return s
    }

    // MARK: Actions

    private func validate() {
        let result = Validator.validate(inputText, as: format)
        outputText = result.formatted ?? ""
        errors     = result.errors
        isValid    = result.isValid
    }

    private func clear() {
        inputText = ""; outputText = ""; errors = []; isValid = nil
    }
}
