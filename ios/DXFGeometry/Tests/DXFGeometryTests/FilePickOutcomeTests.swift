import Testing
import Foundation
@testable import DXFGeometry

/// Dismissing the file picker arrives as a failure. Reporting it as one shows an error for
/// an action that did nothing wrong, and trains people to dismiss alerts without reading.
@Suite("File pick cancellation")
struct FilePickOutcomeTests {
    private var cancelled: NSError {
        NSError(domain: NSCocoaErrorDomain, code: 3072)
    }

    @Test("A cancellation is recognised")
    func cancellation() {
        #expect(FilePickOutcome.isCancellation(cancelled))
    }

    @Test("A real failure is not")
    func realFailure() {
        // File not found, in the same domain.
        #expect(!FilePickOutcome.isCancellation(
            NSError(domain: NSCocoaErrorDomain, code: 4)))
        // The same code in a different domain means something else.
        #expect(!FilePickOutcome.isCancellation(
            NSError(domain: "SomeOtherDomain", code: 3072)))
    }

    @Test("A wrapped cancellation still counts")
    func wrapped() {
        let wrapped = NSError(
            domain: "Wrapper", code: 1,
            userInfo: [NSUnderlyingErrorKey: cancelled])
        #expect(FilePickOutcome.isCancellation(wrapped))
    }

    @Test("A wrapped real failure does not become a cancellation")
    func wrappedReal() {
        let wrapped = NSError(
            domain: "Wrapper", code: 1,
            userInfo: [NSUnderlyingErrorKey: NSError(
                domain: NSCocoaErrorDomain, code: 4)])
        #expect(!FilePickOutcome.isCancellation(wrapped))
    }
}
