import ArgumentParser
import Foundation
import ReviewKit
import ReviewProcess

// NOTE: this file must never be named `main.swift`. In a SwiftPM executable
// target that name means "top-level code", and @main then fails to compile
// with "'main' attribute cannot be used in a module that contains top-level
// code". The same rule applies to the app target's entry point.

@main
struct Review: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Review GitHub pull requests.",
        subcommands: [Show.self, Doctor.self, Version.self]
    )
}

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check that git, gh, the language servers and claude can be found."
    )

    func run() async throws {
        let services = await AppServices.start()
        switch services.environment.source {
        case .loginShell(let shell):
            print("environment: from \(shell) -l -i")
        case .fallback(let reason):
            print("environment: fallback (\(reason))")
        }
        print()

        let statuses = await services.doctor.check()
        for status in statuses {
            let mark = if status.isUsable { "✓" } else if status.tool.isRequired { "✗" } else { "–" }
            print("\(mark) \(status.tool.executableName)")
            if let location = status.location {
                print("    \(location.path)")
            }
            if let version = status.version {
                print("    \(version)")
            }
            if let problem = status.problem {
                print("    \(problem)")
            }
            if status.location == nil {
                print("    not found — \(status.tool.installHint)")
                print("    needed for: \(status.tool.purpose)")
            }
        }

        if statuses.contains(where: { $0.tool.isRequired && !$0.isUsable }) {
            throw ExitCode.failure
        }
    }
}

struct Version: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the version.")

    func run() {
        print("review \(AppServices.version)")
    }
}
