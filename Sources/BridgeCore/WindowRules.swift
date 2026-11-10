import CoreGraphics
import Foundation

public enum WindowRules {
    public static func menuBarStrip(title: String?, frame: CGRect, displayTops: [CGFloat]) -> Bool {
        (title ?? "").trimmingCharacters(in: .whitespaces).isEmpty && frame.height <= 50 && displayTops.contains(frame.minY)
    }

    public static func main(layer: Int, alpha: Double, sharing: Int, title: String?, frame: CGRect, displayTops: [CGFloat]) -> Bool {
        layer == 0 && alpha > 0.01 && sharing != 0 && frame.width >= 120 && frame.height >= 80
            && !menuBarStrip(title: title, frame: frame, displayTops: displayTops)
    }
}
