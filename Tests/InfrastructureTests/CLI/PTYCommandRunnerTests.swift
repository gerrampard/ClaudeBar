import Testing
import Foundation
@testable import Infrastructure

@Suite
struct PTYCommandRunnerTests {

    @Test
    func `which finds system binary`() {
        let path = PTYCommandRunner.which("ls")
        #expect(path != nil)
        #expect(path?.hasSuffix("/ls") == true)
    }

    @Test
    func `which returns nil for unknown binary`() {
        let path = PTYCommandRunner.which("unknown-binary-xyz-123")
        #expect(path == nil)
    }

    @Test
    func `run executes command and returns output`() throws {
        let runner = PTYCommandRunner()
        let result = try runner.run(binary: "echo", send: "", options: .init(extraArgs: ["hello"]))

        #expect(result.exitCode == 0)
        #expect(result.text.contains("hello"))
    }

    @Test
    func `run throws when binary not found`() {
        let runner = PTYCommandRunner()
        #expect(throws: PTYCommandRunner.RunError.self) {
            try runner.run(binary: "unknown-binary-xyz-123", send: "")
        }
    }
}
