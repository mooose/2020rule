import AppKit
import Foundation

extension NSColor {
    static func fromHex(_ hex: String, fallback: NSColor) -> NSColor {
        let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleaned = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw

        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else {
            return fallback
        }

        let r, g, b, a: CGFloat
        if cleaned.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255.0
            g = CGFloat((value >> 16) & 0xFF) / 255.0
            b = CGFloat((value >> 8) & 0xFF) / 255.0
            a = CGFloat(value & 0xFF) / 255.0
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255.0
            g = CGFloat((value >> 8) & 0xFF) / 255.0
            b = CGFloat(value & 0xFF) / 255.0
            a = 1.0
        }

        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexRGB: String {
        guard let converted = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(round(converted.redComponent * 255))
        let g = Int(round(converted.greenComponent * 255))
        let b = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
