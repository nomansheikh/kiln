import Foundation
import Testing
@testable import KilnCore

/// What a helper is started with.
@Suite struct HelperProcessTests {
    @Test func aHelperGetsOnlyTheVariablesItNeeds() {
        let environment = HelperProcess.environment(from: [
            "HOME": "/Users/someone", "TMPDIR": "/tmp/x/", "HF_TOKEN": "hf_secret", "PATH": "/opt/odd/bin",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib", "AWS_SECRET_ACCESS_KEY": "secret",
        ])
        #expect(environment == ["HOME": "/Users/someone", "TMPDIR": "/tmp/x/", "PATH": "/usr/bin:/bin"])
    }

    @Test func theSandboxArgumentsNameTheModelsAndScratchFolders() {
        let arguments = HelperProcess.sandboxArguments(
            models: URL(fileURLWithPath: "/Volumes/Big Disk/models"), scratch: URL(fileURLWithPath: "/tmp/kiln-audio")
        )
        #expect(arguments == ["--sandbox", "/Volumes/Big Disk/models", "/tmp/kiln-audio"])
    }

    @Test func aStartedHelperSeesItsArgumentsAndNotTheAppsSecrets() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-helper-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper.sh")
        try """
        #!/bin/sh
        echo "args: $*"
        echo "secret: ${KILN_TEST_SECRET:-none}"
        echo "path: $PATH"
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        setenv("KILN_TEST_SECRET", "do-not-pass-this-on", 1)
        defer { unsetenv("KILN_TEST_SECRET") }
        let process = try HelperProcess.launch(helper, arguments: ["--sandbox", "/models", "/scratch"])
        var lines: [String] = []
        for await line in process.events {
            lines.append(line)
        }
        #expect(lines == ["args: --sandbox /models /scratch", "secret: none", "path: /usr/bin:/bin"])
    }

    @Test func anEngineStartsItsHelperConfined() async throws {
        let fixture = try EngineFixture()
        // The fake helper writes what it was started with where the image would go.
        let engine = try fixture.engine(onGenerate: """
        printf '%s|%s|%s' "$1" "$2" "$3" > "$output.args"
        printf 'abcdefghijkl' > "$output"
        echo "{\\"type\\":\\"image\\",\\"path\\":\\"$output\\",\\"width\\":2,\\"height\\":2,\\"channels\\":3}"
        echo '{"type":"idle"}'
        """)
        for try await _ in engine.generate(recipe: fixture.recipe, request: fixture.request) {}
        let scratch = fixture.root.appendingPathComponent("scratch")
        let written = try FileManager.default.contentsOfDirectory(at: scratch, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "args" }
        let arguments = try String(contentsOf: try #require(written), encoding: .utf8)
        #expect(arguments == "--sandbox|\(fixture.storage.root.path)|\(scratch.path)")
        await engine.shutdown()
    }

    @Test func aHelperIsNotBelievedAboutAFileTheJobDidNotAskFor() async throws {
        let fixture = try EngineFixture()
        // Twelve bytes that would pass for a 2 by 2 image, somewhere the job never named.
        let elsewhere = fixture.root.appendingPathComponent("someone-elses-file")
        try Data("abcdefghijkl".utf8).write(to: elsewhere)
        let engine = try fixture.engine(onGenerate: """
        echo "{\\"type\\":\\"image\\",\\"path\\":\\"\(elsewhere.path)\\",\\"width\\":2,\\"height\\":2,\\"channels\\":3}"
        echo '{"type":"idle"}'
        """)
        await #expect(throws: EngineError.invalidOutput) {
            for try await _ in engine.generate(recipe: fixture.recipe, request: fixture.request) {}
        }
        await engine.shutdown()
    }
}
