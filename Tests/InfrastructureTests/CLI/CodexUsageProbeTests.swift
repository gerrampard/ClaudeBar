import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

@Suite
struct CodexUsageProbeTests {

    @Test
    func `isAvailable returns false when binary missing`() async {
        let probe = CodexUsageProbe(codexBinary: "non-existent-binary-123")
        #expect(await probe.isAvailable() == false)
    }

    @Test
    func `mapRunError converts errors correctly`() {
        let probe = CodexUsageProbe()
        
        let e1 = probe.mapRunError(.binaryNotFound("codex"))
        if case .cliNotFound(let bin) = e1 { #expect(bin == "codex") } else { Issue.record("Wrong error type") }
        
        let e2 = probe.mapRunError(.timedOut)
        if case .timeout = e2 { } else { Issue.record("Wrong error type") }
        
        let e3 = probe.mapRunError(.launchFailed("msg"))
        if case .executionFailed(let msg) = e3 { #expect(msg == "msg") } else { Issue.record("Wrong error type") }
    }

    @Test
    func `stripANSICodes removes colors`() {
        let input = "\u{1B}[32mGreen\u{1B}[0m Text"
        #expect(CodexUsageProbe.stripANSICodes(input) == "Green Text")
    }

    @Test
    func `extractUsageError finds common errors`() {
        #expect(CodexUsageProbe.extractUsageError("data not available yet") != nil)
        #expect(CodexUsageProbe.extractUsageError("Update available: 1.2.1 ... codex") == .updateRequired)
        #expect(CodexUsageProbe.extractUsageError("All good") == nil)
    }
}
