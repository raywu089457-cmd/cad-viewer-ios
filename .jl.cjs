const fs = require('fs')
const BS = String.fromCharCode(92)
const p = 'verification/dxf-geometry-harness/Sources/verify/main.swift'
let s = fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n')
const anchor = 'section("Bounds")'

const block = [
  'section("A file name survives being put in a script")',
  '// The page is handed the name inside a JavaScript string. Replacing the quote by hand covers',
  '// one character and misses the two that break the call: a backslash starts an escape the',
  '// script does not define, and a newline ends the literal outright.',
  'do {',
  '    let plain = JavaScriptLiteral.quoteOrEmpty("plan.dwg")',
  '    check(plain == "' + BS + '"plan.dwg' + BS + '"", "an ordinary name comes back quoted", plain)',
  '',
  '    let quote = JavaScriptLiteral.quoteOrEmpty("it' + "'" + 's.dwg")',
  '    check(quote.contains(BS + '"\'\''), "a quote in the name is escaped", quote)',
  '    check(quote.hasPrefix("' + BS + '"") && quote.hasSuffix("' + BS + '""),',
  '          "and the literal still closes once", quote)',
  '',
  '    let back = JavaScriptLiteral.quoteOrEmpty("back' + BS + BS + 'slash.dwg")',
  '    check(',
  '        back.contains("back' + BS + BS + BS + BS + 'slash"),',
  '        "a backslash is doubled, not passed through as an escape",',
  '        back)',
  '',
  '    let broken = JavaScriptLiteral.quoteOrEmpty("two" + String(UnicodeScalar(10)) + "lines.dwg")',
  '    check(',
  '        !broken.contains(String(UnicodeScalar(10))),',
  '        "a newline in a name does not end the string",',
  '        broken)',
  '',
  '    // U+2028 is a line terminator in JavaScript and not in JSON. It is rare and it is exactly',
  '    // the kind of character that arrives in a name from elsewhere.',
  '    let sep = JavaScriptLiteral.quoteOrEmpty("a" + String(UnicodeScalar(0x2028)!) + "b")',
  '    check(',
  '        !sep.contains(String(UnicodeScalar(0x2028)!)),',
  '        "U+2028 is escaped too, being a line terminator in JavaScript",',
  '        sep)',
  '}',
  '',
  '',
  anchor,
].join('\n')

if (!s.includes('JavaScriptLiteral')) {
  s = s.replace(anchor, block)
  fs.writeFileSync(p, s)
  console.log('harness added')
}
