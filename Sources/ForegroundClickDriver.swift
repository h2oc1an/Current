import CoreGraphics
import Foundation

struct ForegroundClickDriver: ClickDriver {
    func postClick(to window: WindowDescriptor, globalPoint: CGPoint) throws {
        let events = try MouseClickEvents(globalPoint: globalPoint)
        events.move.post(tap: .cghidEventTap)
        events.down.post(tap: .cghidEventTap)
        events.up.post(tap: .cghidEventTap)
    }
}
