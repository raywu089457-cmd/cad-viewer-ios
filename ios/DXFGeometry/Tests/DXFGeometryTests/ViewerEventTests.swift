import Testing
@testable import DXFGeometry

/// The page-to-app event translation. A mistake here shows up as a spinner that never stops
/// or an error alert on a drawing that opened fine, neither of which a type check catches.
@Suite("Viewer events")
struct ViewerEventTests {
    @Test("The documented events decode")
    func decoding() {
        #expect(ViewerEvent(message: ["event": "ready"]) == .ready)
        #expect(ViewerEvent(message: ["event": "loading"]) == .loading)
        #expect(ViewerEvent(message: ["event": "activated"]) == .activated)
        #expect(
            ViewerEvent(message: ["event": "rendered", "ms": 120])
                == .rendered(milliseconds: 120))
        #expect(
            ViewerEvent(message: ["event": "error", "message": "wasm missing"])
                == .failed("wasm missing"))
    }

    @Test("An event the app does not act on is ignored, not an error")
    func unknownEvents() {
        // The page may grow events the app does not care about; that must not break an open
        // drawing.
        #expect(ViewerEvent(message: ["event": "somethingNew"]) == .ignored)
        #expect(ViewerEvent(message: [:]) == .ignored)
    }

    @Test("A failure with no message still says something")
    func bareError() {
        for message in [["event": "error"], ["event": "error", "message": ""]] {
            guard case let .failed(text) = ViewerEvent(message: message) else {
                Issue.record("a bare error should decode as a failure")
                continue
            }
            #expect(!text.isEmpty)
        }
    }

    @Test("A missing timing does not lose a rendered event")
    func renderedWithoutTiming() {
        #expect(
            ViewerEvent(message: ["event": "rendered"]) == .rendered(milliseconds: nil))
    }

    @Test("Only the in-progress events raise the overlay")
    func statusText() {
        #expect(ViewerEvent.ready.statusText != nil)
        #expect(ViewerEvent.loading.statusText != nil)
        // A spinner left on top of an open drawing is the bug this rule prevents.
        #expect(ViewerEvent.activated.statusText == nil)
        #expect(ViewerEvent.rendered(milliseconds: 1).statusText == nil)
        #expect(ViewerEvent.failed("x").statusText == nil)
        #expect(ViewerEvent.ignored.statusText == nil)
    }

    @Test("The engine counts as warm once it has proved it works")
    func warmEngine() {
        #expect(ViewerEvent.ready.engineIsWarm)
        #expect(ViewerEvent.activated.engineIsWarm)
        #expect(ViewerEvent.rendered(milliseconds: nil).engineIsWarm)
        #expect(!ViewerEvent.loading.engineIsWarm)
        #expect(!ViewerEvent.failed("x").engineIsWarm)
    }

    @Test("Only failures surface an error")
    func errors() {
        #expect(ViewerEvent.failed("boom").errorMessage == "boom")
        #expect(ViewerEvent.ready.errorMessage == nil)
        #expect(ViewerEvent.activated.errorMessage == nil)
        #expect(ViewerEvent.ignored.errorMessage == nil)
    }
}

/// The message a reader sees after waiting for an engine that never answered.
///
/// It is worth pinning because it is the only failure in the DWG path that a reader can act on:
/// everything else is the file or the bundle, and the action is obvious. This one is a silence,
/// and two different causes produce it.
@Suite("Engine readiness")
struct EngineReadinessTests {
    @Test("The timeout says what to try first")
    func firstStep() {
        #expect(EngineReadiness.timeoutMessage.contains("Close the drawing"))
    }

    @Test("And names the other possibility")
    func secondCause() {
        #expect(EngineReadiness.timeoutMessage.contains("viewer itself"))
    }

    @Test("The wait is long enough for a large drawing")
    func patience() {
        // A false failure on a big file is worse than a spinner that lasts longer than needed.
        #expect(EngineReadiness.patience >= .seconds(30))
    }

    @Test("Each DWG failure says what happened, and they are not the same message")
    func dwgFailures() {
        // Each was a literal inside a method that needs a web view, so none could be checked.
        #expect(EngineReadiness.missingBundle.contains("build-for-ios.sh"))
        #expect(EngineReadiness.notADWG.contains("renamed"))
        #expect(!EngineReadiness.noViewerURL.isEmpty)

        let all: Set<String> = [
            EngineReadiness.timeoutMessage, EngineReadiness.missingBundle,
            EngineReadiness.notADWG, EngineReadiness.noViewerURL,
        ]
        #expect(all.count == 4)
    }

    @Test("The details sheet admits the count it does not have")
    func noEntityCount() {
        // A drawing missing its 3D solids looks complete without this, and the reader cannot
        // tell. The message says which number is absent and which format would show it.
        #expect(EngineReadiness.noEntityCount.contains("does not report"))
        #expect(EngineReadiness.noEntityCount.contains("DXF"))
    }
}
