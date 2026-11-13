import CoreGraphics
import Foundation

public enum WindowRules {
    public static func menuBarStrip(title: String?, frame: CGRect, displays: [CGRect]) -> Bool {
        (title ?? "").trimmingCharacters(in: .whitespaces).isEmpty && frame.height <= 50 && displays.contains { $0.minY == frame.minY }
    }

    public static func overlay(layer: Int, frame: CGRect, displays: [CGRect]) -> Bool {
        layer != 0 && displays.contains { frame.contains($0) }
    }

    public static func main(layer: Int, alpha: Double, sharing: Int, title: String?, frame: CGRect, displays: [CGRect]) -> Bool {
        layer == 0 && alpha > 0.01 && sharing != 0 && frame.width >= 120 && frame.height >= 80
            && !menuBarStrip(title: title, frame: frame, displays: displays)
    }
}
