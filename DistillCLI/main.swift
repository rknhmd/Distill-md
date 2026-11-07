//
//  main.swift
//  distill — the command-line companion (and MCP host) for Distill.app
//
//  Ships inside the app bundle at Contents/Helpers/distill and is
//  deliberately UNSANDBOXED: it's spawned directly by users and by MCP
//  clients (Claude Desktop / Claude Code) with arbitrary file paths as
//  arguments, and a sandboxed process couldn't read those paths without
//  a user-selected-file grant — which has no UI in a headless tool.
//  That matches every other Mac CLI; the tool only runs when the user
//  invokes it or configures a client to.
//
//  Argument parsing is hand-rolled — a dependency (swift-argument-parser)
//  isn't worth it for three subcommands and three flags.
//

import Foundation
import DistillCore

/// Read from the Info.plist embedded in this binary
/// (CREATE_INFOPLIST_SECTION_IN_BINARY), which inherits MARKETING_VERSION
/// from Config/Version.xcconfig — so the CLI, the MCP server, and the app
/// can never report different versions.
let toolVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

// MARK: - Output helpers

nonisolated func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

nonisolated func printUsage() {
    print("""
    distill \(toolVersion) — documents in, AI-ready Markdown out (on-device)

    USAGE:
      distill convert <file>... [--output-dir <dir>] [--front-matter] [--stdout]
      distill list-formats
      distill install-cli
      distill mcp

    SUBCOMMANDS:
      convert        Convert files to Markdown. By default the .md is written
                     next to each source file (never overwriting — name-2.md, …).
      list-formats   Show the supported input formats.
      install-cli    Symlink this binary into /usr/local/bin so `distill`
                     works from any terminal.
      mcp            Run as an MCP (Model Context Protocol) server on stdio,
                     for Claude Desktop / Claude Code integration.

    CONVERT OPTIONS:
      --output-dir <dir>   Write .md files into <dir> instead of next to sources.
      --front-matter       Prepend the YAML metadata header.
      --extract-images     Save embedded images into <name>-assets/ next to
                           the .md, linked in place (ignored with --stdout).
      --stdout             Print Markdown to stdout instead of writing files.
    """)
}

// MARK: - Subcommand: convert

@MainActor
func runConvert(_ arguments: [String]) async -> Int32 {
    var inputs: [URL] = []
    var outputDir: URL?
    var wantsFrontMatter = false
    var wantsImages = false
    var toStdout = false

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--output-dir":
            index += 1
            guard index < arguments.count else {
                printError("error: --output-dir needs a path")
                return 1
            }
            outputDir = URL(fileURLWithPath: arguments[index], isDirectory: true)
        case "--front-matter":
            wantsFrontMatter = true
        case "--extract-images":
            wantsImages = true
        case "--stdout":
            toStdout = true
        case "--help", "-h":
            printUsage()
            return 0
        default:
            if argument.hasPrefix("-") {
                printError("error: unknown option \(argument)")
                return 1
            }
            inputs.append(URL(fileURLWithPath: argument))
        }
        index += 1
    }

    guard !inputs.isEmpty else {
        printError("error: no input files. Usage: distill convert <file>...")
        return 1
    }
    if let outputDir {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    var failureCount: Int32 = 0
    var missingRun: [String] = []   // consecutive not-found args, see below

    /// Unquoted paths with spaces arrive as several argv entries and fail
    /// one by one ("Ch25" + "textbook.pdf"). When the pieces joined with
    /// spaces name a real file, say so instead of leaving two cryptic
    /// errors. (Quoted paths always worked — this is shell word-splitting.)
    func flushMissingRunHint() {
        defer { missingRun = [] }
        guard missingRun.count >= 2 else { return }
        let joined = missingRun.joined(separator: " ")
        if FileManager.default.fileExists(atPath: joined) {
            printError("hint: these look like one path split by the shell — quote it: \"\(joined)\"")
        }
    }

    for url in inputs {
        guard FileManager.default.fileExists(atPath: url.path) else {
            printError("\(url.lastPathComponent): no such file")
            failureCount += 1
            missingRun.append(url.relativePath)
            continue
        }
        flushMissingRunHint()
        guard let type = FileType.detect(from: url) else {
            printError("\(url.lastPathComponent): unsupported format")
            failureCount += 1
            continue
        }

        do {
            let options = ConversionOptions(extractImages: wantsImages && !toStdout)
            let result = try await ConversionEngine.convert(fileAt: url, type: type, options: options)
            var markdown = result.markdown

            if wantsFrontMatter,
               !FrontMatter.contentAlreadyHasFrontMatter(markdown, type: type) {
                markdown = FrontMatter.header(
                    sourceName: url.lastPathComponent,
                    format: type,
                    result: result,
                    tokenEstimate: TokenEstimator.estimate(markdown)
                ) + markdown
            }

            if toStdout {
                print(markdown, terminator: markdown.hasSuffix("\n") ? "" : "\n")
            } else {
                let folder = outputDir ?? url.deletingLastPathComponent()
                let destination = OutputNaming.uniqueDestination(
                    in: folder,
                    baseName: url.deletingPathExtension().lastPathComponent
                )
                markdown = try AssetWriter.materialize(
                    markdown: markdown, assets: result.assets, besideMarkdownAt: destination
                )
                try Data(markdown.utf8).write(to: destination, options: .atomic)
                printError("\(url.lastPathComponent) → \(destination.path)")
            }
        } catch {
            let reason = (error as? ConversionError)?.errorDescription ?? error.localizedDescription
            printError("\(url.lastPathComponent): \(reason)")
            failureCount += 1
        }
    }
    flushMissingRunHint()
    return failureCount == 0 ? 0 : 2
}

// MARK: - Subcommand: list-formats

nonisolated func runListFormats() -> Int32 {
    print("Supported input formats:")
    for type in FileType.allCases {
        print("  \(type.displayName)")
    }
    return 0
}

// MARK: - Subcommand: install-cli

nonisolated func runInstallCLI() -> Int32 {
    // arguments[0] may be a symlink (that's the point of this command) —
    // resolve to the real binary inside the app bundle.
    let binaryPath = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath().path
    let linkPath = "/usr/local/bin/distill"
    let fm = FileManager.default

    do {
        try fm.createDirectory(atPath: "/usr/local/bin", withIntermediateDirectories: true)
        if fm.fileExists(atPath: linkPath) {
            try fm.removeItem(atPath: linkPath)
        }
        try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: binaryPath)
        print("Installed: \(linkPath) → \(binaryPath)")
        return 0
    } catch {
        printError("""
        Couldn't write to /usr/local/bin (\(error.localizedDescription)).
        Run it with sudo instead:

          sudo mkdir -p /usr/local/bin
          sudo ln -sf '\(binaryPath)' \(linkPath)
        """)
        return 1
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

guard let subcommand = arguments.first else {
    printUsage()
    exit(1)
}

switch subcommand {
case "convert":
    exit(await runConvert(Array(arguments.dropFirst())))
case "list-formats":
    exit(runListFormats())
case "install-cli":
    exit(runInstallCLI())
case "mcp":
    exit(await runMCPServer())
case "--version", "-v":
    print(toolVersion)
    exit(0)
case "--help", "-h", "help":
    printUsage()
    exit(0)
default:
    printError("error: unknown subcommand '\(subcommand)'\n")
    printUsage()
    exit(1)
}
