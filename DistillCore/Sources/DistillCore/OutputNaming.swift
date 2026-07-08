//
//  OutputNaming.swift
//  DistillCore
//
//  The never-overwrite naming rule, shared by the app's OutputWriter
//  and the CLI: name.md, name-2.md, name-3.md, …
//

import Foundation

public nonisolated enum OutputNaming {

    public static func uniqueDestination(in folder: URL, baseName: String) -> URL {
        var candidate = folder.appendingPathComponent(baseName + ".md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName)-\(suffix).md")
            suffix += 1
        }
        return candidate
    }
}
