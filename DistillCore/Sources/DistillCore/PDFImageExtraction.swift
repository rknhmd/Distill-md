//
//  PDFImageExtraction.swift
//  DistillCore
//
//  Pulls raster images out of a PDF page's resources (XObjects) via
//  CoreGraphics. Two encodings cover nearly all real documents:
//
//    DCTDecode  — the stream *is* a JPEG; saved byte-for-byte as .jpg
//    FlateDecode — zlib'd raw pixels; rebuilt into a CGImage and saved
//                  as .png (DeviceRGB / DeviceGray only)
//
//  Exotic cases (CCITT fax, JBIG2, indexed palettes, ICC arrays) are
//  skipped deliberately — wrong colors are worse than no image.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PDFImageExtraction {

    struct PageImage {
        let data: Data
        let fileExtension: String
    }

    /// Images on one page (1-based CGPDF page numbering), in resource
    /// order. Tiny images (< 8px a side) are ignored as decoration.
    static func images(inPageAt pageNumber: Int, of document: CGPDFDocument) -> [PageImage] {
        guard let page = document.page(at: pageNumber),
              let pageDict = page.dictionary else { return [] }

        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources else { return [] }

        var xObjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xObjects),
              let xObjects else { return [] }

        var found: [PageImage] = []
        CGPDFDictionaryApplyBlock(xObjects, { _, object, _ in
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let streamDict = CGPDFStreamGetDictionary(stream) else { return true }

            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                  let subtype, String(cString: subtype) == "Image" else { return true }

            var width = 0, height = 0
            CGPDFDictionaryGetInteger(streamDict, "Width", &width)
            CGPDFDictionaryGetInteger(streamDict, "Height", &height)
            guard width >= 8, height >= 8 else { return true }

            var format = CGPDFDataFormat.raw
            guard let cfData = CGPDFStreamCopyData(stream, &format) else { return true }
            let data = cfData as Data

            switch format {
            case .jpegEncoded:
                found.append(PageImage(data: data, fileExtension: "jpg"))
            case .JPEG2000:
                found.append(PageImage(data: data, fileExtension: "jp2"))
            case .raw:
                if let png = encodeRawPixels(data, streamDict: streamDict, width: width, height: height) {
                    found.append(PageImage(data: png, fileExtension: "png"))
                }
            @unknown default:
                break
            }
            return true
        }, nil)

        return found
    }

    /// FlateDecode output is raw pixel rows. Rebuild a CGImage for the
    /// two simple color spaces and PNG-encode it; anything fancier
    /// returns nil.
    private static func encodeRawPixels(
        _ data: Data,
        streamDict: CGPDFDictionaryRef,
        width: Int,
        height: Int
    ) -> Data? {
        var bitsPerComponent = 8
        CGPDFDictionaryGetInteger(streamDict, "BitsPerComponent", &bitsPerComponent)
        guard bitsPerComponent == 8 else { return nil }

        var colorSpaceName: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(streamDict, "ColorSpace", &colorSpaceName),
              let colorSpaceName else { return nil }

        let componentCount: Int
        let colorSpace: CGColorSpace
        switch String(cString: colorSpaceName) {
        case "DeviceRGB":
            componentCount = 3
            colorSpace = CGColorSpaceCreateDeviceRGB()
        case "DeviceGray":
            componentCount = 1
            colorSpace = CGColorSpaceCreateDeviceGray()
        default:
            return nil   // Indexed / ICCBased arrays land here — skip.
        }

        let bytesPerRow = width * componentCount
        guard data.count >= bytesPerRow * height,
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 8 * componentCount,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
