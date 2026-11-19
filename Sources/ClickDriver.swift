import CoreGraphics
import Foundation

enum ClickChannel {
    case foreground
    case publicPID
    case windowRouted
    // 目标窗口内命中了可按下元素，经 AXPress 直接触发，未产生鼠标事件。
    case windowAccessibility
}

protocol ClickDriver {
    func postClick(to window: WindowDescriptor, globalPoint: CGPoint) throws
}

struct MouseClickEvents {
    let move: CGEvent
    let down: CGEvent
    let up: CGEvent

    init(globalPoint: CGPoint) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: globalPoint,
            mouseButton: .left
        ), let down = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: globalPoint,
            mouseButton: .left
        ), let up = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: globalPoint,
            mouseButton: .left
        ) else {
            throw ClickError.eventCreationFailed
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        self.move = move
        self.down = down
        self.up = up
    }
}
