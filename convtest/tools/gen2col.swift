// Generates the multi-column PDF fixtures: twocol.pdf (title + two
// text columns, must be re-ordered left-then-right) and onecol.pdf
// (single column, must NOT be touched).
// Usage: swift gen2col.swift <output-dir>

import Foundation
import CoreText
import CoreGraphics

let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

func draw(_ text: String, in rect: CGRect, context: CGContext, size: CGFloat = 11) {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let attributed = NSAttributedString(string: text, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    CTFrameDraw(frame, context)
}

func makePDF(named name: String, drawPage: (CGContext) -> Void) {
    let url = outDir.appendingPathComponent(name)
    var mediaBox = pageRect
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("no context for \(name)")
    }
    context.beginPDFPage(nil)
    drawPage(context)
    context.endPDFPage()
    context.closePDF()
    print("wrote \(name)")
}

let leftText = (1...8).map { "LEFT-\($0) the quick brown fox jumps over the lazy dog again and again." }.joined(separator: " ")
let rightText = (1...8).map { "RIGHT-\($0) pack my box with five dozen liquor jugs every single time." }.joined(separator: " ")
let singleText = (1...8).map { "SINGLE-\($0) a full width paragraph flowing across the entire page body." }.joined(separator: " ")

makePDF(named: "twocol.pdf") { ctx in
    draw("TWO COLUMN TEST DOCUMENT HEADLINE ACROSS THE FULL WIDTH",
         in: CGRect(x: 50, y: 712, width: 512, height: 40), context: ctx, size: 16)
    draw(leftText, in: CGRect(x: 50, y: 60, width: 236, height: 630), context: ctx)
    draw(rightText, in: CGRect(x: 326, y: 60, width: 236, height: 630), context: ctx)
}

makePDF(named: "onecol.pdf") { ctx in
    draw("ONE COLUMN CONTROL DOCUMENT",
         in: CGRect(x: 50, y: 712, width: 512, height: 40), context: ctx, size: 16)
    draw(singleText, in: CGRect(x: 50, y: 60, width: 512, height: 630), context: ctx)
}
