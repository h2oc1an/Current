import CoreGraphics

enum WindowGeometry {
    static func appKitFrame(forQuartzRect rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: mainScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func relativePoint(forAppKitPoint point: CGPoint, inAppKitFrame frame: CGRect) -> CGPoint {
        CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
    }

    static func quartzPoint(forRelativePoint point: CGPoint, in bounds: CGRect) -> CGPoint? {
        guard point.x.isFinite,
              point.y.isFinite,
              point.x >= 0,
              point.y >= 0,
              point.x < bounds.width,
              point.y < bounds.height else {
            return nil
        }
        return CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y)
    }
}
