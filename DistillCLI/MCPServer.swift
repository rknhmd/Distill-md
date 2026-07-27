//
//  MCPServer.swift
//  distill
//
//  `distill mcp` — a Model Context Protocol server over stdio, so MCP
//  clients (Claude Desktop, Claude Code) can call Distill's converters
//  directly. stdout carries the protocol; all logging goes to stderr.
//
//  Client config (Claude Desktop / Claude Code):
//    { "mcpServers": { "distill": {
//        "command": "/Applications/Distill.app/Contents/Helpers/distill",
//        "args": ["mcp"] } } }
//

import Foundation
import DistillCore
import MCP

@MainActor
func runMCPServer() async -> Int32 {
    let server = Server(
        name: "distill",
        version: toolVersion,
        capabilities: .init(tools: .init(listChanged: false))
    )

    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: distillTools)
    }

    await server.withMethodHandler(CallTool.self) { params in
        await handleToolCall(params)
    }

    do {
        let transport = StdioTransport()
        try await server.start(transport: transport)
        // Serve until the client closes the pipe.
        await server.waitUntilCompleted()
        return 0
    } catch {
        printError("mcp: \(error.localizedDescription)")
        return 1
    }
}

// MARK: - Tool definitions

private nonisolated let distillTools: [Tool] = [
    Tool(
        name: "convert_to_markdown",
        description: """
        Convert a document (PDF, Word, PowerPoint, Excel, HTML, CSV, ZIP \
        archives, and more) to clean Markdown and return the Markdown \
        text directly. A ZIP becomes one combined document with a section \
        per contained file. Runs fully on-device. Use convert_file \
        instead if the result should be written to disk.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the document to convert"),
                ]),
                "front_matter": .object([
                    "type": .string("boolean"),
                    "description": .string("Prepend a YAML metadata header (default false)"),
                ]),
            ]),
            "required": .array([.string("path")]),
        ])
    ),
    Tool(
        name: "convert_file",
        description: """
        Convert a document to Markdown and write the .md file to disk \
        (next to the source, or into output_dir). Never overwrites: \
        name.md, name-2.md, … Returns the path of the written file.
        """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object([
                    "type": .string("string"),
                    "description": .string("Absolute path to the document to convert"),
                ]),
                "output_dir": .object([
                    "type": .string("string"),
                    "description": .string("Directory for the .md (default: next to the source)"),
                ]),
                "front_matter": .object([
                    "type": .string("boolean"),
                    "description": .string("Prepend a YAML metadata header (default false)"),
                ]),
                "extract_images": .object([
                    "type": .string("boolean"),
                    "description": .string("Save embedded images into <name>-assets/ next to the .md (default false)"),
                ]),
            ]),
            "required": .array([.string("path")]),
        ])
    ),
    Tool(
        name: "list_supported_formats",
        description: "List the document formats Distill.md can convert to Markdown.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ])
    ),
]

// MARK: - Tool dispatch

private nonisolated func handleToolCall(_ params: CallTool.Parameters) async -> CallTool.Result {
    switch params.name {
    case "convert_to_markdown":
        guard let path = params.arguments?["path"]?.stringValue else {
            return .init(content: [.text("Missing required argument: path")], isError: true)
        }
        let wantsFrontMatter = params.arguments?["front_matter"]?.boolValue ?? false
        do {
            let (markdown, _, _) = try await convertDocument(path: path, frontMatter: wantsFrontMatter)
            return .init(content: [.text(markdown)], isError: false)
        } catch {
            return .init(content: [.text(errorText(error, path: path))], isError: true)
        }

    case "convert_file":
        guard let path = params.arguments?["path"]?.stringValue else {
            return .init(content: [.text("Missing required argument: path")], isError: true)
        }
        let wantsFrontMatter = params.arguments?["front_matter"]?.boolValue ?? false
        let wantsImages = params.arguments?["extract_images"]?.boolValue ?? false
        let outputDir = params.arguments?["output_dir"]?.stringValue
        do {
            let (markdown, sourceURL, conversionResult) = try await convertDocument(
                path: path, frontMatter: wantsFrontMatter, extractImages: wantsImages
            )
            let folder = outputDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? sourceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = OutputNaming.uniqueDestination(
                in: folder,
                baseName: sourceURL.deletingPathExtension().lastPathComponent
            )
            let finalMarkdown = try AssetWriter.materialize(
                markdown: markdown, assets: conversionResult.assets, besideMarkdownAt: destination
            )
            try Data(finalMarkdown.utf8).write(to: destination, options: .atomic)
            return .init(content: [.text(destination.path)], isError: false)
        } catch {
            return .init(content: [.text(errorText(error, path: path))], isError: true)
        }

    case "list_supported_formats":
        let formats = FileType.allCases.map(\.displayName).joined(separator: ", ")
        return .init(content: [.text(formats)], isError: false)

    default:
        return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
    }
}

// MARK: - Shared conversion plumbing

private nonisolated func convertDocument(
    path: String,
    frontMatter: Bool,
    extractImages: Bool = false
) async throws -> (markdown: String, sourceURL: URL, result: ConversionResult) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ConversionError.fileUnreadable
    }
    guard let type = FileType.detect(from: url) else {
        throw ConversionError.unsupportedType
    }

    let result = try await ConversionEngine.convert(
        fileAt: url, type: type, options: ConversionOptions(extractImages: extractImages)
    )
    var markdown = result.markdown
    if frontMatter, !FrontMatter.contentAlreadyHasFrontMatter(markdown, type: type) {
        markdown = FrontMatter.header(
            sourceName: url.lastPathComponent,
            format: type,
            result: result,
            tokenEstimate: TokenEstimator.estimate(markdown)
        ) + markdown
    }
    return (markdown, url, result)
}

private nonisolated func errorText(_ error: any Error, path: String) -> String {
    let reason = (error as? ConversionError)?.errorDescription ?? error.localizedDescription
    return "\(URL(fileURLWithPath: path).lastPathComponent): \(reason)"
}
