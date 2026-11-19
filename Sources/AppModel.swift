import AppKit
import Combine
import CoreGraphics
import Foundation

func diagLog(_ message: String) {
    let line = "\(Date()): \(message)\n"
    let url = URL(fileURLWithPath: "/tmp/windowclicker-diag.log")
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

func frontDesc() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "nil" }
    return "\(app.localizedName ?? "?")(\(app.processIdentifier))"
}

struct RepeatConfiguration: Equatable {
    static let minimumInterval: TimeInterval = 0.01
    static let maximumInterval: TimeInterval = 3_600

    let interval: TimeInterval
    let count: Int

    init?(interval: TimeInterval, count: Int) {
        guard interval.isFinite,
              interval >= Self.minimumInterval,
              interval <= Self.maximumInterval,
              count > 0 else {
            return nil
        }
        self.interval = interval
        self.count = count
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var windows: [WindowDescriptor] = []
    @Published var selectedWindowID: CGWindowID? {
        didSet {
            guard oldValue != selectedWindowID else { return }
            selectedRelativePoint = nil
            clearMessages()
        }
    }
    @Published var clickMode: ClickMode = .foreground
    @Published private(set) var selectedRelativePoint: CGPoint?
    @Published var intervalText = "1"
    @Published var countText = "10"
    @Published private(set) var isWorking = false
    @Published private(set) var isRepeating = false
    @Published private(set) var completedCount = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    var selectedWindow: WindowDescriptor? {
        guard let selectedWindowID else { return nil }
        return windows.first { $0.id == selectedWindowID }
    }

    private let windowService = WindowService()
    private let clickEngine = ClickEngine()
    private let windowOrdering = WindowOrdering()
    private var pickerController: PointPickerController?
    private var repeatTask: Task<Void, Never>?

    init() {
        refreshWindows()
    }

    func refreshWindows() {
        windows = windowService.visibleWindows()
        if let selectedWindowID, !windows.contains(where: { $0.id == selectedWindowID }) {
            self.selectedWindowID = nil
        }
    }

    func choosePoint() {
        clearMessages()
        guard let selectedWindowID,
              let window = windowService.window(withID: selectedWindowID) else {
            errorMessage = ClickError.targetWindowUnavailable.localizedDescription
            refreshWindows()
            return
        }

        let controller = PointPickerController()
        pickerController = controller
        controller.present(for: window) { [weak self] result in
            guard let self else { return }
            pickerController = nil
            switch result {
            case .picked(let point):
                selectedRelativePoint = point
                statusMessage = "已选点：X \(Int(point.x))，Y \(Int(point.y))（相对窗口左上角）"
            case .cancelled:
                statusMessage = "已取消选点"
            case .failed(let message):
                errorMessage = message
            }
        }
    }

    func performSingleClick() async {
        guard !isWorking else { return }
        clearMessages()
        guard let selection = validatedSelection(), ensureAccessibilityPermission() else { return }

        isWorking = true
        defer { isWorking = false }
        do {
            let channel = try await performClick(windowID: selection.windowID, point: selection.point, mode: clickMode)
            switch (clickMode, channel) {
            case (.windowRouted, .windowAccessibility):
                statusMessage = "已在后台直接按下目标控件（AXPress，未产生鼠标事件，不会置前）。"
            case (.windowRouted, .windowRouted):
                statusMessage = "坐标处没有可用的辅助功能控件，已回退合成点击；目标应用可能不响应。"
            case (.windowRouted, _):
                statusMessage = "窗口路由不可用，已回退公开 PID 通道；目标应用可能不响应。"
            case (.publicPID, _):
                statusMessage = "公开 PID 事件已发送；目标应用可能不响应。"
            default:
                statusMessage = "单击事件已发送。"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRepeating() {
        guard !isWorking else { return }
        clearMessages()
        guard let selection = validatedSelection(), ensureAccessibilityPermission() else { return }
        guard let interval = Double(intervalText.trimmingCharacters(in: .whitespaces)),
              let count = Int(countText.trimmingCharacters(in: .whitespaces)),
              let configuration = RepeatConfiguration(interval: interval, count: count) else {
            errorMessage = "间隔需在 0.01～3600 秒之间，次数必须为正整数。"
            return
        }

        let mode = clickMode
        isWorking = true
        isRepeating = true
        completedCount = 0
        statusMessage = "准备连点…"

        repeatTask = Task { [weak self] in
            guard let self else { return }
            var didFail = false

            for index in 1...configuration.count {
                if Task.isCancelled { break }
                do {
                    _ = try await performClick(windowID: selection.windowID, point: selection.point, mode: mode)
                    completedCount = index
                    statusMessage = "已发送 \(index)/\(configuration.count) 次"
                } catch is CancellationError {
                    break
                } catch {
                    errorMessage = error.localizedDescription
                    didFail = true
                    break
                }

                if index < configuration.count {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(configuration.interval * 1_000_000_000))
                    } catch {
                        break
                    }
                }
            }

            let wasCancelled = Task.isCancelled
            repeatTask = nil
            isWorking = false
            isRepeating = false
            if wasCancelled {
                statusMessage = "已停止连点，共发送 \(completedCount) 次。"
            } else if didFail {
                statusMessage = "连点已停止，共发送 \(completedCount) 次。"
            } else {
                statusMessage = "连点已完成，共发送 \(completedCount) 次。"
            }
        }
    }

    func stopRepeating() {
        guard repeatTask != nil else { return }
        repeatTask?.cancel()
        statusMessage = "正在停止…"
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func validatedSelection() -> (windowID: CGWindowID, point: CGPoint)? {
        guard let selectedWindowID, let selectedRelativePoint else {
            errorMessage = "请先选择窗口并完成选点。"
            return nil
        }
        return (selectedWindowID, selectedRelativePoint)
    }

    private func ensureAccessibilityPermission() -> Bool {
        guard !clickEngine.isAccessibilityTrusted else { return true }
        clickEngine.requestAccessibilityPermission()
        errorMessage = ClickError.accessibilityPermissionRequired.localizedDescription
        return false
    }

    private func performClick(windowID: CGWindowID, point: CGPoint, mode: ClickMode) async throws -> ClickChannel {
        guard let window = windowService.window(withID: windowID) else {
            throw ClickError.targetWindowUnavailable
        }

        if mode == .foreground,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != window.ownerPID {
            try clickEngine.activate(window)
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        try Task.checkCancellation()
        guard let latestWindow = windowService.window(withID: windowID) else {
            throw ClickError.targetWindowUnavailable
        }
        let priorFront = NSWorkspace.shared.frontmostApplication?.processIdentifier

        guard mode == .windowRouted else {
            return try clickEngine.postClick(to: latestWindow, relativePoint: point, mode: mode)
        }

        // 记录点击前位于目标之上、且与目标重叠的窗口（front-to-back），用于撤销 raise。
        let aboveIDs = overlappingWindowsAbove(windowID: windowID, targetBounds: latestWindow.bounds)
        let signal = ClickCompletionSignal()
        // 监听与点击并行：点击在后台线程投递，主线程高频观察 z-order，
        // 目标一旦被抬到这些窗口上方就立即抬回，把可见闪烁压到 1~2 帧。
        let watcher = Task { @MainActor in
            await restoreAfterBackgroundClick(
                priorFront: priorFront,
                targetPID: latestWindow.ownerPID,
                windowID: windowID,
                aboveIDs: aboveIDs,
                completion: signal
            )
        }
        do {
            let channel = try await postClickOnBackground(to: latestWindow, relativePoint: point, mode: mode)
            signal.isFinished = true
            await watcher.value
            return channel
        } catch {
            signal.isFinished = true
            await watcher.value
            throw error
        }
    }

    private final class ClickCompletionSignal: @unchecked Sendable {
        var isFinished = false
    }

    private func postClickOnBackground(
        to window: WindowDescriptor,
        relativePoint: CGPoint,
        mode: ClickMode
    ) async throws -> ClickChannel {
        let engine = clickEngine
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInteractive).async {
                do {
                    continuation.resume(returning: try engine.postClick(to: window, relativePoint: relativePoint, mode: mode))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func overlappingWindowsAbove(windowID: CGWindowID, targetBounds: CGRect) -> [CGWindowID] {
        let ordered = windowService.zOrderedWindows()
        guard let index = ordered.firstIndex(where: { $0.id == windowID }) else { return [] }
        return ordered[..<index]
            .filter { $0.id != windowID && $0.bounds.intersects(targetBounds) }
            .map(\.id)
    }

    // 合成点击不移动真实鼠标，但 WindowServer 仍会把被点中的后台窗口抬到后台窗口栈的
    // 顶部（实测 AppKit、Electron 都会）。客户进程无法直接重排其他应用的窗口：
    // SLSOrderWindow 跨进程返回 1000。可行做法是让各窗口所属应用自己 AXRaise 回来——
    // 不激活应用、不改变 key 窗口，只恢复层叠顺序（cua-driver key_focus_guard 同法）。
    // 应用激活与窗口置前是分离的，两者都要恢复；若用户在此期间切走则不干预。
    //
    // 本方法在点击投递期间并行运行（点击在后台线程），8ms 轮询以便在 raise 生效后
    // 立刻抬回，避免目标窗口明显闪现。
    private func restoreAfterBackgroundClick(
        priorFront: pid_t?,
        targetPID: pid_t,
        windowID: CGWindowID,
        aboveIDs: [CGWindowID],
        completion: ClickCompletionSignal
    ) async {
        guard !aboveIDs.isEmpty || priorFront != nil else { return }
        let started = Date()
        var restoreRounds = 0
        var calmChecks = 0
        var sawRaise = false
        var raisedPIDs = Set<pid_t>()

        // 目标自激活或 AXRaise 偶发把某个被抬窗口的应用带到前台时，还原用户原前台应用。
        func restoreFrontmostIfHijacked() {
            guard let priorFront, priorFront != targetPID,
                  let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  front != priorFront,
                  front == targetPID || raisedPIDs.contains(front) else { return }
            let ok = NSRunningApplication(processIdentifier: priorFront)?.activate() ?? false
            diagLog("restore frontmost activate returned \(ok)")
        }

        // 点击序列约 150ms，raise 发生在目标 down（约 116ms）；点击结束后再观察一小段
        // 处理滞后 raise。总时长上限 1.5 秒。
        while Date().timeIntervalSince(started) < 1.5 {
            if let priorFront, priorFront != targetPID,
               let front = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               front != priorFront, front != targetPID, !raisedPIDs.contains(front) {
                // 用户自己切走了，不干预。
                diagLog("restore aborted: front changed to \(front)")
                return
            }

            let ordered = windowService.zOrderedWindows()
            guard let targetIndex = ordered.firstIndex(where: { $0.id == windowID }) else { return }
            let displaced = aboveIDs.filter { id in
                guard let index = ordered.firstIndex(where: { $0.id == id }) else { return false }
                return index > targetIndex
            }

            if displaced.isEmpty {
                calmChecks += 1
                // 点击已结束：没发生过 raise 时再等 3 次（约 24ms）即可收工；
                // 已发生过则多观察约 160ms，防止应用延迟二次 raise。
                if completion.isFinished, calmChecks >= (sawRaise ? 20 : 3) {
                    if sawRaise { diagLog("restore completed after \(restoreRounds) round(s)") }
                    return
                }
            } else if restoreRounds < 3 {
                restoreRounds += 1
                sawRaise = true
                calmChecks = 0
                let elapsed = Int(Date().timeIntervalSince(started) * 1000)
                diagLog("restore raise at +\(elapsed)ms: \(displaced)")
                // 从被压到目标下方的最底窗口开始逐个抬回，还原原始相对顺序。
                for id in displaced.reversed() {
                    guard let window = ordered.first(where: { $0.id == id }) else { continue }
                    raisedPIDs.insert(window.ownerPID)
                    let ok = windowOrdering.raise(windowID: id, ownerPID: window.ownerPID)
                    if !ok { diagLog("restore raise \(id) (\(window.ownerName)) returned false") }
                }
                let doneMs = Int(Date().timeIntervalSince(started) * 1000)
                diagLog("restore round \(restoreRounds) done at +\(doneMs)ms")
                restoreFrontmostIfHijacked()
            } else {
                return
            }

            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    private func clearMessages() {
        statusMessage = nil
        errorMessage = nil
    }
}
