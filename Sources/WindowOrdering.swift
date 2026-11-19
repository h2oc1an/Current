import ApplicationServices
import CoreGraphics
import Foundation

// 撤销合成点击导致的目标窗口置前。
//
// 跨进程调用 SkyLight 的 SLSOrderWindow 会被 WindowServer 拒绝（返回 1000），
// 客户进程无法直接重排其他应用的窗口顺序。可行做法是让「原本在目标之上的窗口」
// 所在的进程自己把自己的窗口 AXRaise 回来：AXRaise 不激活应用、不改变 key 窗口，
// 只会把该窗口抬到当前前台应用窗口之下、其他后台窗口之上（cua-driver 的
// key_focus_guard 使用同一技巧恢复用户窗口）。
struct WindowOrdering {
    private typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32

    // 私有符号：把 AXUIElement 窗口映射回它的 CGWindowID。
    private let getWindow: AXGetWindow?

    init() {
        getWindow = Self.resolve("_AXUIElementGetWindow")
    }

    private static func resolve<T>(_ name: String) -> T? {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    // 在该窗口所属进程内找到对应 AX 窗口并执行 AXRaise。
    func raise(windowID: CGWindowID, ownerPID: pid_t) -> Bool {
        guard let getWindow, windowID != kCGNullWindowID else { return false }
        let application = AXUIElementCreateApplication(ownerPID)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return false
        }
        for window in windows {
            var wid: CGWindowID = 0
            if getWindow(window, &wid) == 0, wid == windowID {
                return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
            }
        }
        return false
    }
}
