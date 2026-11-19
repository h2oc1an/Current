import CoreGraphics
import Foundation

struct PublicPIDClickDriver: ClickDriver {
    func postClick(to window: WindowDescriptor, globalPoint: CGPoint) throws {
        let events = try MouseClickEvents(globalPoint: globalPoint)
        for event in [events.move, events.down, events.up] {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(window.ownerPID))
            event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(getpid()))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.id))
            event.setIntegerValueField(
                .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                value: Int64(window.id)
            )
            event.timestamp = DispatchTime.now().uptimeNanoseconds
        }
        events.move.postToPid(window.ownerPID)
        events.down.postToPid(window.ownerPID)
        events.up.postToPid(window.ownerPID)
    }
}
