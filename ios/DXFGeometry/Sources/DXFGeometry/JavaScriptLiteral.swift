import Foundation

/// Turns a Swift string into a JavaScript string literal.
///
/// Hand-rolled escaping is how a name with a backslash, a newline or a lone quote breaks the
/// call it is embedded in. `back\slash.dwg` becomes `'back\slash.dwg'`, and `\s` is not a
/// JavaScript escape, so the page receives a different name than the file has — or the script
/// fails to parse. A real newline inside the quotes ends the literal outright.
///
/// `JSONSerialization` already knows every rule: it escapes the quote, the backslash, the
/// control characters and `\u2028`/`\u2029`, which are line terminators in JavaScript but not
/// in JSON. A JSON string is a JavaScript string, so nothing else is needed.
public enum JavaScriptLiteral {
    /// The string as a quoted JavaScript literal, or `nil` if it cannot be encoded.
    public static func quote(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
            let array = String(data: data, encoding: .utf8)
        else { return nil }
        // `["..."]` — drop the brackets, keep the quoted element.
        let start = array.index(after: array.startIndex)
        let end = array.index(before: array.endIndex)
        var literal = String(array[start..<end])

        // JSON leaves U+2028 and U+2029 raw; JavaScript treats both as line terminators, so a
        // name holding one ends the literal. This is the one rule JSON does not already have.
        // A backslash and the code point, not the character.
        literal = literal.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        literal = literal.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return literal
    }

    /// The same, falling back to an empty literal rather than failing a drawing that would
    /// otherwise open. An unnamed drawing is worse than no drawing, but only slightly, and the
    /// page copes with an empty name.
    public static func quoteOrEmpty(_ value: String) -> String {
        quote(value) ?? "\"\""
    }
}
