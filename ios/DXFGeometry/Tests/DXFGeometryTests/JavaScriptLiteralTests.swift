import Foundation
import Testing

@testable import DXFGeometry

@Suite("A name put inside a script")
struct JavaScriptLiteralTests {
    @Test("An ordinary name comes back quoted and unchanged")
    func plain() throws {
        let literal = try #require(JavaScriptLiteral.quote("plan.dwg"))
        #expect(literal == "\"plan.dwg\"")
    }

    @Test("A quote in the name does not close the literal early")
    func quote() throws {
        let literal = try #require(JavaScriptLiteral.quote("it's.dwg"))
        #expect(literal.hasPrefix("\""))
        #expect(literal.hasSuffix("\""))
        // One pair of quotes only: the name's own quote sits inside, unescaped, because the
        // literal is double-quoted. What must not happen is a second, bare quote.
        #expect(literal.filter { $0 == "\"" }.count == 2)
        #expect(literal.contains("it's.dwg"))
    }

    @Test("A backslash is doubled rather than passed through")
    func backslash() throws {
        // `back\slash.dwg` as a Swift literal. Hand-rolled escaping left this alone, so the
        // page received `\s`, which is not a JavaScript escape.
        let name = "back" + String(UnicodeScalar(92)) + "slash.dwg"
        let literal = try #require(JavaScriptLiteral.quote(name))
        #expect(literal.contains("back" + String(UnicodeScalar(92)) + String(UnicodeScalar(92))))
    }

    @Test("A newline in a name cannot end the literal")
    func newline() throws {
        let name = "two" + String(UnicodeScalar(10)) + "lines.dwg"
        let literal = try #require(JavaScriptLiteral.quote(name))
        #expect(!literal.contains(String(UnicodeScalar(10))))
        #expect(literal.contains("\\n"))
    }

    @Test("U+2028 is escaped, because JavaScript ends a line there and JSON does not")
    func lineSeparator() throws {
        let separator = try #require(UnicodeScalar(0x2028))
        let literal = try #require(JavaScriptLiteral.quote("a" + String(separator) + "b"))
        #expect(!literal.contains(String(separator)))
        #expect(literal.contains("\\u2028"))

        let paragraph = try #require(UnicodeScalar(0x2029))
        let other = try #require(JavaScriptLiteral.quote("a" + String(paragraph) + "b"))
        #expect(!other.contains(String(paragraph)))
    }

    @Test("A name that cannot be encoded still leaves a usable literal")
    func fallback() {
        // The page copes with an empty name; it does not cope with a call that fails to parse.
        #expect(JavaScriptLiteral.quoteOrEmpty("plan.dwg") != "\"\"")
        #expect(!JavaScriptLiteral.quoteOrEmpty("").isEmpty)
    }
}
