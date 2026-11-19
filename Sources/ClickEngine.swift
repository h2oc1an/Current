import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum ClickMode: String, CaseIterable, Identifiable {
    case foreground
    case windowRouted
    case publicPID

    var id: Self { self }

    var title: String {
        switch self {
        case .foreground:
            return "前台模式（稳定）"
        case .windowRouted:
            return "窗口路由模式（实验）"
        case .publicPID:
            return "公开 PID 模式（对照）"
        }
    }
}

enum ClickError: LocalizedError {
    case accessibilityPermissionRequired
    case targetWindowUnavailable
    case selectedPointOutsideWindow
    case applicationActivationFailed
    case eventCreationFailed
    case windowRoutingUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "需要辅助功能权限。请打开系统设置，允许“窗口点击器”后重试。"
        case .targetWindowUnavailable:
            return "目标窗口已关闭、最小化或不在当前桌面，已停止点击。"
        case .selectedPointOutsideWindow:
            return "目标窗口缩小后已不包含选定位置，已停止点击。请重新选点。"
        case .applicationActivationFailed:
            return "无法激活目标应用，请确认应用仍在运行。"
        case .eventCreationFailed:
            return "无法创建鼠标事件。"
        case .windowRoutingUnavailable:
            return "当前系统缺少窗口路由所需的私有符号。"
        }
    }
}

struct ClickEngine {
    private let foregroundDriver = ForegroundClickDriver()
    private let publicPIDDriver = PublicPIDClickDriver()
    private let windowRoutedDriver = WindowRoutedClickDriver()
    private let axClicker = AXWindowClicker()

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    func activate(_ window: WindowDescriptor) throws {
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID),
              application.activate() else {
            throw ClickError.applicationActivationFailed
        }
    }

    // 返回实际使用的投递通道；窗口路由符号缺失时回退公开 PID 通道。
    @discardableResult
    func postClick(to window: WindowDescriptor, relativePoint: CGPoint, mode: ClickMode) throws -> ClickChannel {
        guard let globalPoint = WindowGeometry.quartzPoint(forRelativePoint: relativePoint, in: window.bounds) else {
            throw ClickError.selectedPointOutsideWindow
        }

        switch mode {
        case .foreground:
            try foregroundDriver.postClick(to: window, globalPoint: globalPoint)
            return .foreground
        case .publicPID:
            try publicPIDDriver.postClick(to: window, globalPoint: globalPoint)
            return .publicPID
        case .windowRouted:
            // 优先走 AXPress：完全不产生鼠标事件，目标窗口不会置前，是唯一无感知路径。
            // 坐标处没有可按下元素（自绘界面、游戏等）时才回退合成点击。
            let axStarted = Date()
            let axPressed = axClicker.press(at: globalPoint, in: window)
            diagLog("ax press \(axPressed) in \(Int(Date().timeIntervalSince(axStarted) * 1000))ms")
            if axPressed {
                return .windowAccessibility
            }
            if windowRoutedDriver.isAvailable {
                try windowRoutedDriver.postClick(to: window, globalPoint: globalPoint)
                return .windowRouted
            }
            try publicPIDDriver.postClick(to: window, globalPoint: globalPoint)
            return .publicPID
        }
    }
}
