import Foundation
import ReviewCore
import ReviewProcess

/// A throwaway "GitHub": a local repository with a base branch, a PR head
/// published as `refs/pull/<n>/head`, and a commit on the base branch after
/// the PR branched — so the merge base is not the base tip, as in real life.
struct FixtureRepository {
    let directory: URL
    let source: URL
    let reference = PullRequestReference(owner: "acme", repository: "widgets", number: 7)
    let baseSHA: String
    let headSHA: String
    let branchPointSHA: String
    /// A global config that sets everything that could change `git diff`'s
    /// output. GitClient must produce parseable output regardless.
    let hostileConfig: URL

    var environment: [String: String] {
        [
            "PATH": "/usr/bin:/bin",
            "HOME": directory.path,
            "GIT_CONFIG_GLOBAL": hostileConfig.path,
            "GIT_CONFIG_NOSYSTEM": "1",
        ]
    }

    var pullRequest: PullRequest {
        PullRequest(
            reference: reference, title: "Fixture", body: "", author: "octocat", state: .open, isDraft: false,
            base: PullRequest.Branch(name: "main", sha: baseSHA),
            head: PullRequest.Branch(name: "feature", sha: headSHA)
        )
    }

    static let mainGo = (1...40).map { "line \($0)" }.joined(separator: "\n") + "\n"

    static func make() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-fixture-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let hostileConfig = directory.appendingPathComponent("hostile.gitconfig")
        try """
            [diff]
                noprefix = true
                mnemonicPrefix = true
                renames = false
                context = 10
                external = /bin/false
            [color]
                diff = always
                ui = always
            [core]
                quotePath = true
                abbrev = 7
            [uploadpack]
                allowFilter = true
                allowAnySHA1InWant = true
            """.write(to: hostileConfig, atomically: true, encoding: .utf8)

        let fixture = Shell(directory: source, environment: [
            "PATH": "/usr/bin:/bin", "HOME": directory.path,
            "GIT_CONFIG_GLOBAL": hostileConfig.path, "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "f@example.com",
            "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "f@example.com",
        ])

        try await fixture.git("init", "--quiet", "--initial-branch=main")
        try fixture.write("main.go", mainGo)
        try fixture.write("old.go", "package widgets\n\nfunc Old() {}\n\nfunc Keep() {}\n")
        try fixture.write("my file.go", "package widgets\n// spaced\n")
        try fixture.write("café.go", "package widgets\n// accented\n")
        try fixture.write("gone.ts", "export const gone = 1\n")
        try fixture.write("run.sh", "#!/bin/sh\necho hi\n")
        try fixture.write("crlf.txt", "one\r\ntwo\r\nthree\r\n")
        try fixture.write("noeol.txt", "no newline")
        try fixture.writeBytes("logo.png", [0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02])
        try await fixture.git("add", "-A")
        try await fixture.git("commit", "--quiet", "-m", "base")
        let branchPoint = try await fixture.git("rev-parse", "HEAD")

        try await fixture.git("checkout", "--quiet", "-b", "feature")
        var lines = mainGo.split(separator: "\n").map(String.init)
        lines[2] = "line 3 changed"
        lines.insert("inserted after 20", at: 20)
        lines.remove(at: 35)
        try fixture.write("main.go", lines.joined(separator: "\n") + "\n")
        try await fixture.git("mv", "old.go", "renamed.go")
        try fixture.write("renamed.go", "package widgets\n\nfunc New() {}\n\nfunc Keep() {}\n")
        try fixture.write("my file.go", "package widgets\n// spaced, edited\n")
        try fixture.write("café.go", "package widgets\n// accented, edited\n")
        try await fixture.git("rm", "--quiet", "gone.ts")
        try fixture.write("new.ts", "export const added = 2\nexport const more = 3\n")
        // A generated file, as GitHub decides it: by `.gitattributes`.
        try fixture.write(".gitattributes", "*.pb.go linguist-generated=true\nnot-generated.go linguist-generated=false\n")
        try fixture.write("api.pb.go", "package widgets\n// Code generated. DO NOT EDIT.\n")
        try fixture.write("not-generated.go", "package widgets\n")
        // On disk, not `update-index --chmod`: `add -A` below re-reads the
        // mode from the working tree and would undo it.
        try fixture.makeExecutable("run.sh")
        try fixture.write("crlf.txt", "one\r\nTWO\r\nthree\r\n")
        try fixture.write("noeol.txt", "still no newline")
        try fixture.writeBytes("logo.png", [0x89, 0x50, 0x4E, 0x47, 0x00, 0x09, 0x09])
        try await fixture.git("add", "-A")
        try await fixture.git("commit", "--quiet", "-m", "feature")
        let head = try await fixture.git("rev-parse", "HEAD")
        try await fixture.git("update-ref", "refs/pull/7/head", head)

        // main moves on after the branch point.
        try await fixture.git("checkout", "--quiet", "main")
        try fixture.write("unrelated.go", "package widgets\n")
        try await fixture.git("add", "-A")
        try await fixture.git("commit", "--quiet", "-m", "meanwhile on main")
        let base = try await fixture.git("rev-parse", "HEAD")

        return Self(
            directory: directory, source: source, baseSHA: base, headSHA: head,
            branchPointSHA: branchPoint, hostileConfig: hostileConfig
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Runs fixture-building commands in one directory.
struct Shell {
    let directory: URL
    let environment: [String: String]

    @discardableResult
    func git(_ arguments: String...) async throws -> String {
        let output = try await Subprocess.run(
            URL(fileURLWithPath: "/usr/bin/git"), arguments,
            environment: environment, currentDirectory: directory
        )
        guard output.succeeded else {
            throw FixtureError(message: "git \(arguments.joined(separator: " ")): \(output.stderrText)")
        }
        return output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func write(_ path: String, _ text: String) throws {
        try text.write(to: directory.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }

    func makeExecutable(_ path: String) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: directory.appendingPathComponent(path).path
        )
    }

    func writeBytes(_ path: String, _ bytes: [UInt8]) throws {
        try Data(bytes).write(to: directory.appendingPathComponent(path))
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
