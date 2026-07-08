//
//  AssetCollector.swift
//  DistillCore
//
//  Per-conversion accumulator for extracted images. Content-hash
//  dedupe: the same picture embedded five times becomes one asset file
//  with five links pointing at it.
//

import Foundation
import CryptoKit

nonisolated final class AssetCollector {

    private var nameByHash: [String: String] = [:]
    private var counter = 1
    private(set) var assets: [ExtractedAsset] = []

    /// Registers image bytes and returns the asset name placeholders
    /// should reference. Identical data returns the existing name.
    func register(data: Data, preferredExtension: String) -> String {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        if let existing = nameByHash[digest] {
            return existing
        }
        let name = "image\(counter).\(preferredExtension)"
        counter += 1
        nameByHash[digest] = name
        assets.append(ExtractedAsset(name: name, data: data))
        return name
    }

    /// "![](distill-asset://image1.png)"
    static func placeholderLink(for name: String) -> String {
        "![](\(AssetWriter.placeholderPrefix)\(name))"
    }
}
