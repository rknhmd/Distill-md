//
//  TokenEstimator.swift
//  Distill
//
//  Zero-dependency LLM token estimate. Flat chars÷4 is decent for
//  English prose but drifts badly elsewhere, so this adjusts by content:
//
//    prose        ~4 chars/token   (the classic BPE rule of thumb)
//    code, URLs   ~3 chars/token   (symbols fragment into more tokens)
//    CJK          ~1.3 chars/token (most ideographs are 1+ tokens each)
//
//  Still an estimate — the UI keeps the "~" and the tooltip. A real
//  tokenizer vocabulary is deliberately NOT bundled (app size).
//

import Foundation

nonisolated enum TokenEstimator {

    static func estimate(_ text: String) -> Int {
        var total = 0.0
        var insideCodeFence = false

        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideCodeFence.toggle()
                total += Double(line.count) / 3.0
                continue
            }
            if insideCodeFence {
                total += Double(line.count + 1) / 3.0
                continue
            }
            total += estimateProseLine(line)
        }
        return max(0, Int(total.rounded()))
    }

    private static func estimateProseLine(_ line: String) -> Double {
        var proseChars = 0
        var cjkChars = 0
        var urlChars = 0

        for word in line.split(separator: " ", omittingEmptySubsequences: false) {
            if word.contains("://") {
                // Bare URLs and [text](https://…) links both land here —
                // link syntax tokenizes densely too.
                urlChars += word.count
            } else {
                for scalar in word.unicodeScalars {
                    if isCJK(scalar) { cjkChars += 1 } else { proseChars += 1 }
                }
            }
            proseChars += 1   // the separating space
        }
        return Double(proseChars) / 4.0 + Double(cjkChars) / 1.3 + Double(urlChars) / 3.0
    }

    /// Han ideographs, kana, Hangul, and full-width forms — the scripts
    /// where "one character ≈ one token" holds.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x9FFF,     // CJK radicals, kana, unified ideographs
             0xAC00...0xD7AF,     // Hangul syllables
             0xF900...0xFAFF,     // CJK compatibility ideographs
             0xFF00...0xFFEF:     // full-width forms
            return true
        default:
            return false
        }
    }
}
