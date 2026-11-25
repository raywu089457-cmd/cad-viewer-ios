// Writes the two PDFs the fixtures need: a valid one-page document, and one that parses but
// holds no pages. Hand-built rather than committed as binary, so a reader can see what is in
// them and a change to either is reviewable in a diff.
//
//   node verification/make-pdf.mjs <dir>
import { writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'

const dir = process.argv[2]
if (!dir) {
  console.error('usage: node verification/make-pdf.mjs <dir>')
  process.exit(2)
}
mkdirSync(dir, { recursive: true })

// A minimal one-page PDF: the smallest thing a reader will open and draw a page for.
const onePage = [
  '%PDF-1.4',
  '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj',
  '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj',
  '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >> endobj',
  'trailer << /Root 1 0 R /Size 4 >>',
  '%%EOF',
  '',
].join(String.fromCharCode(10))
writeFileSync(join(dir, 'one-page.pdf'), onePage)

// A document whose page tree is empty: PDFKit produces a document and reports zero pages, which
// is the case the viewer has a message for and nothing tested.
const noPages = [
  '%PDF-1.4',
  '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj',
  '2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj',
  'trailer << /Root 1 0 R /Size 3 >>',
  '%%EOF',
  '',
].join(String.fromCharCode(10))
writeFileSync(join(dir, 'no-pages.pdf'), noPages)

console.log('wrote one-page.pdf and no-pages.pdf')
