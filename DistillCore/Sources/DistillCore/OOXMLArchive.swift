//
//  OOXMLArchive.swift
//  Distill
//
//  Office files (.docx, .pptx, .xlsx) are ZIP archives full of XML.
//  This thin wrapper around ZIPFoundation reads entries out of one; the
//  DOCX and PPTX converters build on it.
//

import Foundation
import ZIPFoundation

nonisolated struct OOXMLArchive {

    private let archive: Archive

    init(url: URL) throws {
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            // Not a ZIP at all (or unreadable) — e.g. an old binary .doc
            // renamed to .docx.
            throw ConversionError.corruptDocument
        }
    }

    /// Reads one entry fully into memory. Office XML parts are small
    /// (text, not media), so this is fine.
    func data(at path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw ConversionError.corruptDocument
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    /// Like `data(at:)` but for optional parts (numbering.xml, notes, …).
    func dataIfPresent(at path: String) -> Data? {
        guard archive[path] != nil else { return nil }
        return try? data(at: path)
    }

    /// All entry paths matching a prefix/suffix — used to enumerate
    /// slide XML files inside a .pptx.
    func paths(withPrefix prefix: String, suffix: String) -> [String] {
        archive.compactMap { entry in
            let path = entry.path
            return path.hasPrefix(prefix) && path.hasSuffix(suffix) ? path : nil
        }
    }
}
