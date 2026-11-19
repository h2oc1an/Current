import CoreGraphics
import Foundation

// 窗口路由驱动：通过私有字段 51（CGWindowID）让 WindowServer 把事件命中测试到
// 指定后台窗口，而不是按屏幕位置命中（后者会跳过非 key 窗口，导致 win=0）。
//
// 事件序列采用 cua-driver 的 Chromium 兼容完整配方（AppKit 同样适用）：
//   mouseMoved(目标) → 15ms → primerDown(-1,-1) → 1ms → primerUp(-1,-1)
//   → 100ms → targetDown(目标) → 30ms → targetUp(目标)
// 屏幕外 primer down/up 满足 Chromium/Electron 的激活门控——否则第一次点击
// 只用于激活窗口，控件不响应（实测 QQ 症状）；f0 为手势阶段标记。
// 发送用 CGEventPostToPid（SLEventPostToPid 的 IOHID 路径会触发点击激活前置窗口）。
// 点击前先 focus-without-raise（见 FocusWithoutRaise.swift），防止置前窗口。
// 私有符号全部 dlsym 运行时解析，不链接；符号缺失时 isAvailable=false，由上层回退。
final class WindowRoutedClickDriver: ClickDriver {
    private typealias SetIntegerField = @convention(c) (CGEvent, UInt32, Int64) -> Void
    private typealias SetWindowLocation = @convention(c) (CGEvent, Double, Double) -> Void

    // SLEventSetIntegerValueField 是非校验 setter；公开 CGEventSetIntegerValueField
    // 可能静默忽略未公开索引 51/58，因此必须用它。
    private let setIntegerField: SetIntegerField?
    private let setWindowLocation: SetWindowLocation?
    private let focusWithoutRaise = FocusWithoutRaise()

    // cua-driver 实测：macOS 27 起 WindowServer 把 CGEventSetWindowLocation 的
    // stamp 视为窗口局部坐标；之前版本视为屏幕坐标并自行换算局部坐标。
    private static let windowLocationIsWindowLocal =
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

    init() {
        setIntegerField = Self.resolve("SLEventSetIntegerValueField")
        setWindowLocation = Self.resolve("CGEventSetWindowLocation")
    }

    var isAvailable: Bool {
        setIntegerField != nil && setWindowLocation != nil
    }

    private static func resolve<T>(_ name: String) -> T? {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private struct RouteStep {
        let type: CGEventType
        let location: CGPoint   // 事件屏幕坐标
        let stamp: CGPoint      // CGEventSetWindowLocation
        let clickState: Int64
        let phase: Int64        // f0：手势阶段（move=2，primerDown=1，primerUp=2，target=3）
        let delayAfter: useconds_t
    }

    func postClick(to window: WindowDescriptor, globalPoint: CGPoint) throws {
        guard let setIntegerField, let setWindowLocation else {
            throw ClickError.windowRoutingUnavailable
        }
        guard window.id != kCGNullWindowID, window.ownerPID > 0 else {
            throw ClickError.targetWindowUnavailable
        }

        // 先让目标窗口成为 AppKit-key（不 raise），防止 mouseDown 触发置前。
        if focusWithoutRaise.apply(to: window) {
            usleep(50_000)  // 等 AppKit 完成 key 窗口路由更新
        }

        // 窗口内命中测试点：macOS 27+ 用窗口局部坐标，之前用屏幕坐标。
        let stampedTarget: CGPoint
        if Self.windowLocationIsWindowLocal {
            stampedTarget = CGPoint(
                x: globalPoint.x - window.bounds.minX,
                y: globalPoint.y - window.bounds.minY
            )
        } else {
            stampedTarget = globalPoint
        }
        let offScreen = CGPoint(x: -1, y: -1)
        let steps = [
            RouteStep(type: .mouseMoved, location: globalPoint, stamp: stampedTarget,
                      clickState: 0, phase: 2, delayAfter: 15_000),
            RouteStep(type: .leftMouseDown, location: offScreen, stamp: offScreen,
                      clickState: 1, phase: 1, delayAfter: 1_000),
            RouteStep(type: .leftMouseUp, location: offScreen, stamp: offScreen,
                      clickState: 1, phase: 2, delayAfter: 100_000),
            // 目标 down/up 的 clickState 必须为 0：任何非零 clickState 都会让目标应用
            // 把窗口抬到前面（实测 AppKit、Chromium 均如此）。0 只是让 Chromium 不合成
            // click 事件（本路径仅在 AXPress 失败时使用），mousedown/mouseup 仍正常投递。
            RouteStep(type: .leftMouseDown, location: globalPoint, stamp: stampedTarget,
                      clickState: 0, phase: 3, delayAfter: 30_000),
            RouteStep(type: .leftMouseUp, location: globalPoint, stamp: stampedTarget,
                      clickState: 0, phase: 3, delayAfter: 0),
        ]

        let source = CGEventSource(stateID: .hidSystemState)
        let clickGroup = Int64(mach_absolute_time() & 0x7fff_ffff)
        let windowID = Int64(window.id)

        // 全部事件先创建并 stamp 完毕再发送：发送循环不会失败，
        // 保证 Down/Up 不可分割，异步取消不会留下按下状态。
        var events: [(event: CGEvent, delayAfter: useconds_t)] = []
        for step in steps {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: step.type,
                mouseCursorPosition: step.location,
                mouseButton: .left
            ) else {
                throw ClickError.eventCreationFailed
            }
            setWindowLocation(event, Double(step.stamp.x), Double(step.stamp.y))
            setIntegerField(event, 0, step.phase)
            setIntegerField(event, 1, step.clickState)
            setIntegerField(event, 3, 0)                        // buttonNumber：0=左键
            setIntegerField(event, 7, 3)                        // subtype：3=NSEventSubtypeTouch
            setIntegerField(event, 40, Int64(window.ownerPID))  // 目标 PID
            setIntegerField(event, 58, clickGroup)              // click group：整组事件同组
            // primer 也必须路由到窗口（51/91/92）：QQ(Electron) 的激活门控
            // 在窗口级，win=0 的 primer 不满足；由此产生的 raise 由上层恢复 z-order。
            setIntegerField(event, 51, windowID)                // windowNumber：核心路由字段
            setIntegerField(event, 91, windowID)                // windowUnderMousePointer
            setIntegerField(event, 92, windowID)                // ...ThatCanHandleThisEvent
            events.append((event, step.delayAfter))
        }

        for (event, delay) in events {
            // 只用 CGEventPostToPid：SLEventPostToPid 走 IOHID 路径，会触发
            // WindowServer 的"点击激活"导致目标窗口前置（实测回归）。
            event.postToPid(window.ownerPID)
            if delay > 0 { usleep(delay) }
        }
    }
}
