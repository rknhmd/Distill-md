//
//  TextFileReader.swift
//  Distill
//
//  Shared helper for loading text files without knowing their encoding
//  up front. Used by the plain-text, CSV, and HTML converters.
//

import Foundation

nonisolated enum TextFileReader {

    /// Reads a file and decodes it to a String, trying encodings from most
    /// to least likely. ISO Latin-1 is the last resort because it can decode
    /// any byte sequence (it just maps bytes 1:1), so this only throws for
    /// unreadable or empty files.
    static func read(_ url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConversionError.fileUnreadable
        }
        guard !data.isEmpty else { throw ConversionError.emptyFile }

        // UTF-16 files start with a byte-order mark (FF FE or FE FF).
        // Check for it explicitly because UTF-16 data often *also* decodes
        // as garbage Latin-1, so order matters.
        if data.count >= 2 {
            let b0 = data[data.startIndex], b1 = data[data.startIndex + 1]
            if (b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF),
               let text = String(data: data, encoding: .utf16) {
                return stripBOM(text)
            }
        }

        if let text = String(data: data, encoding: .utf8) {
            return stripBOM(text)
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw ConversionError.textEncodingUnrecognized
    }

    /// Removes a leading byte-order mark if the decoder kept it as a
    /// zero-width character.
    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}
