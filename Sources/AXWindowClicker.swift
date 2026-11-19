import ApplicationServices
import CoreGraphics
import Foundation

// 无感点击：在目标窗口的 AX 树里找到坐标处可按下元素并执行 AXPress。
//
// 与合成鼠标事件不同，AXPress 不产生任何鼠标事件，因此目标窗口不会被
// WindowServer/应用抬到前面，也不占用真实鼠标和焦点。
//
// Chromium/Electron 默认不暴露网页内容树，需先向应用设置
// AXEnhancedUserInterface + AXManualAccessibility，等待渲染进程构建树后重试。
// 两个属性都是标准 AX 属性；不支持的应用会返回错误并被忽略。
// 找不到可按下元素时返回 false，由调用方回退到窗口路由点击。
final class AXWindowClicker {
    private typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> Int32

    // 私有符号：把 AXUIElement 窗口映射回 CGWindowID。
    private let getWindow: AXGetWindow?
    // 已经开启过辅助功能树的应用，避免每次点击都等待构建。
    private var preparedPIDs = Set<pid_t>()

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

    func press(at point: CGPoint, in window: WindowDescriptor) -> Bool {
        guard let getWindow, window.id != kCGNullWindowID, window.ownerPID > 0 else { return false }
        let application = AXUIElementCreateApplication(window.ownerPID)

        if let element = axWindow(in: application, matching: window.id, getWindow: getWindow)
            .flatMap({ pressableElement(in: $0, at: point) }) {
            return performPress(element)
        }

        guard preparedPIDs.insert(window.ownerPID).inserted else { return false }
        AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        usleep(180_000)  // 等渲染进程按需构建可访问性树

        if let element = axWindow(in: application, matching: window.id, getWindow: getWindow)
            .flatMap({ pressableElement(in: $0, at: point) }) {
            return performPress(element)
        }
        return false
    }

    private func axWindow(in application: AXUIElement, matching id: CGWindowID, getWindow: AXGetWindow) -> AXUIElement? {
        guard let windows = copyAttribute(application, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        for window in windows {
            var wid: CGWindowID = 0
            if getWindow(window, &wid) == 0, wid == id {
                return window
            }
        }
        return nil
    }

    // 命中最深处（面积最小）的可按下元素。
    private func pressableElement(in root: AXUIElement, at point: CGPoint) -> AXUIElement? {
        var best: AXUIElement?
        var bestArea = CGFloat.greatestFiniteMagnitude
        var visited = 0

        func walk(_ element: AXUIElement, depth: Int) {
            visited += 1
            if depth > 40 || visited > 4000 { return }

            let frame = frame(of: element)
            let contains = frame?.contains(point) ?? false
            if contains, hasPressAction(element) {
                let area = (frame?.width ?? 0) * (frame?.height ?? 0)
                if area < bestArea {
                    best = element
                    bestArea = area
                }
            }
            // 只下探包含该点的分支；无 frame 的容器仅在前几层继续。
            if contains || (frame == nil && depth < 3) {
                for child in children(of: element) {
                    walk(child, depth: depth + 1)
                }
            }
        }

        walk(root, depth: 0)
        return best
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let value = copyAttribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private func hasPressAction(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else {
            return false
        }
        return actions.contains(kAXPressAction as String)
    }

    private func performPress(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        (copyAttribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private func copyAttribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
