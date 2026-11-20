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

enum ExecutionMode: String, Hashable, Codable {
    case single
    case flow
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
            // 步骤坐标相对窗口左上角，换窗口后旧步骤不再有效。
            steps.removeAll()
            clearMessages()
        }
    }
    // 默认使用兼容性最好的前台模式；无感的窗口路由模式需用户显式选择。
    @Published var clickMode: ClickMode = .foreground
    @Published var executionMode: ExecutionMode = .single
    @Published private(set) var selectedRelativePoint: CGPoint?
    @Published var intervalText = "1"
    @Published var countText = "10"
    @Published private(set) var steps: [ClickStep] = []
    @Published var flowCycleText = "1"
    @Published private(set) var isWorking = false
    @Published private(set) var isRepeating = false
    @Published private(set) var isRunningFlow = false
    @Published private(set) var completedCount = 0
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var tasks: [ClickTask] = []
    @Published private(set) var selectedTaskID: UUID?
    @Published private(set) var isCreatingTask = false
    @Published var taskNameText = "任务 1"

    var showsConfiguration: Bool {
        selectedTaskID != nil || isCreatingTask
    }

    var selectedWindow: WindowDescriptor? {
        guard let selectedWindowID else { return nil }
        return windows.first { $0.id == selectedWindowID }
    }

    private let windowService = WindowService()
    private let clickEngine = ClickEngine()
    private let windowOrdering = WindowOrdering()
    private let taskStore: TaskStore
    private var pickerController: PointPickerController?
    private var repeatTask: Task<Void, Never>?
    private var flowTask: Task<Void, Never>?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init(taskStore: TaskStore = TaskStore()) {
        self.taskStore = taskStore
        do {
            let library = try taskStore.load()
            tasks = library.tasks
            if let selectedTaskID = library.selectedTaskID,
               tasks.contains(where: { $0.id == selectedTaskID }) {
                self.selectedTaskID = selectedTaskID
            }
        } catch {
            errorMessage = "任务读取失败：\(error.localizedDescription)"
        }
        refreshWindows()
        if let task = selectedTask {
            taskNameText = task.name
            apply(configuration: task.configuration)
            showMissingWindowMessageIfNeeded(for: task.configuration)
        }
        installEmergencyHotkey()
    }

    func refreshWindows() {
        windows = windowService.visibleWindows()
        if let selectedWindowID, !windows.contains(where: { $0.id == selectedWindowID }) {
            self.selectedWindowID = nil
        }
    }

    private var selectedTask: ClickTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first { $0.id == selectedTaskID }
    }

    func startNewTask() {
        guard !isWorking else { return }
        selectedTaskID = nil
        isCreatingTask = true
        taskNameText = nextTaskName()
        apply(configuration: .initial)
        clearMessages()
        persistTaskLibrary()
    }

    func selectTask(id: UUID) {
        guard !isWorking else { return }
        if selectedTaskID == id {
            deselectTask()
            return
        }
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        clearMessages()
        selectedTaskID = id
        isCreatingTask = false
        taskNameText = task.name
        apply(configuration: task.configuration)
        showMissingWindowMessageIfNeeded(for: task.configuration)
        if errorMessage == nil {
            statusMessage = "已加载任务“\(task.name)”。"
        }
        persistTaskLibrary()
    }

    func deselectTask() {
        guard !isWorking else { return }
        selectedTaskID = nil
        isCreatingTask = false
        clearMessages()
        persistTaskLibrary()
    }

    func saveTask() {
        guard !isWorking, showsConfiguration else { return }
        clearMessages()
        let trimmedName = taskNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? nextTaskName() : trimmedName
        taskNameText = name
        let task = ClickTask(
            id: selectedTaskID ?? UUID(),
            name: name,
            configuration: captureConfiguration()
        )
        var library = TaskLibrary(tasks: tasks, selectedTaskID: selectedTaskID)
        library.upsert(task)
        tasks = library.tasks
        selectedTaskID = library.selectedTaskID
        isCreatingTask = false
        if persistTaskLibrary() {
            statusMessage = "已保存任务“\(name)”。"
        }
    }

    func deleteSelectedTask() {
        guard !isWorking, let task = selectedTask else { return }
        clearMessages()
        var library = TaskLibrary(tasks: tasks, selectedTaskID: selectedTaskID)
        library.delete(id: task.id)
        tasks = library.tasks
        selectedTaskID = nil
        isCreatingTask = false
        taskNameText = nextTaskName()
        apply(configuration: .initial)
        if persistTaskLibrary() {
            statusMessage = "已删除任务“\(task.name)”。"
        }
    }

    private func captureConfiguration() -> TaskConfiguration {
        TaskConfiguration(
            window: selectedWindow.map(SavedWindow.init) ?? selectedTask?.configuration.window,
            selectedRelativePoint: selectedRelativePoint,
            clickMode: clickMode,
            executionMode: executionMode,
            intervalText: intervalText,
            countText: countText,
            steps: steps,
            flowCycleText: flowCycleText
        )
    }

    private func apply(configuration: TaskConfiguration) {
        selectedWindowID = configuration.window?.matchingWindow(in: windows)?.id
        selectedRelativePoint = configuration.selectedRelativePoint
        clickMode = configuration.clickMode
        executionMode = configuration.executionMode
        intervalText = configuration.intervalText
        countText = configuration.countText
        steps = configuration.steps
        flowCycleText = configuration.flowCycleText
    }

    private func showMissingWindowMessageIfNeeded(for configuration: TaskConfiguration) {
        if configuration.window != nil && selectedWindowID == nil {
            errorMessage = "任务的原目标窗口不可用或无法唯一匹配，请打开原窗口后重新加载任务，或重新选择窗口。"
        }
    }

    private func nextTaskName() -> String {
        let existingNames = Set(tasks.map(\.name))
        var index = tasks.count + 1
        while existingNames.contains("任务 \(index)") {
            index += 1
        }
        return "任务 \(index)"
    }

    @discardableResult
    private func persistTaskLibrary() -> Bool {
        do {
            try taskStore.save(TaskLibrary(tasks: tasks, selectedTaskID: selectedTaskID))
            return true
        } catch {
            errorMessage = "任务保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func choosePoint() {
        clearMessages()
        guard let window = validatedWindow() else { return }
        presentPicker(for: window) { [weak self] point in
            guard let self else { return }
            selectedRelativePoint = point
            statusMessage = "已选点：X \(Int(point.x))，Y \(Int(point.y))（相对窗口左上角）"
        }
    }

    func addStep() {
        guard !isWorking else { return }
        clearMessages()
        guard let window = validatedWindow() else { return }
        presentPicker(for: window) { [weak self] point in
            guard let self else { return }
            steps.append(ClickStep(point: point))
            statusMessage = "已添加第 \(steps.count) 步：X \(Int(point.x))，Y \(Int(point.y))"
        }
    }

    func repickStep(id: UUID) {
        guard !isWorking else { return }
        clearMessages()
        guard let window = validatedWindow() else { return }
        presentPicker(for: window) { [weak self] point in
            guard let self, let index = steps.firstIndex(where: { $0.id == id }) else { return }
            steps[index].point = point
            statusMessage = "第 \(index + 1) 步已更新为 X \(Int(point.x))，Y \(Int(point.y))"
        }
    }

    func removeStep(id: UUID) {
        guard !isWorking else { return }
        steps.removeAll { $0.id == id }
        clearMessages()
    }

    func updateStepMinimumInterval(id: UUID, text: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].minimumIntervalText = text
    }

    func updateStepMaximumInterval(id: UUID, text: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].maximumIntervalText = text
    }

    // 复用选点面板：仅处理取消与失败提示，成功时交回调用方。
    private func presentPicker(for window: WindowDescriptor, onPicked: @escaping (CGPoint) -> Void) {
        let controller = PointPickerController()
        pickerController = controller
        controller.present(for: window) { [weak self] result in
            guard let self else { return }
            pickerController = nil
            switch result {
            case .picked(let point):
                onPicked(point)
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

    func startFlow() {
        guard !isWorking else { return }
        clearMessages()
        guard let window = validatedWindow(), ensureAccessibilityPermission() else { return }

        let plan: FlowConfiguration.Plan
        switch FlowConfiguration.plan(steps: steps, cyclesText: flowCycleText) {
        case .failure(let error):
            errorMessage = error.message
            return
        case .success(let value):
            plan = value
        }

        let mode = clickMode
        isWorking = true
        isRunningFlow = true
        statusMessage = "准备运行事件流…"
        diagLog("flow start: window=\(window.id) steps=\(plan.steps.count) cycles=\(plan.cycles) mode=\(mode.title)")

        flowTask = Task { [weak self] in
            guard let self else { return }
            var cycle = 0
            var totalClicks = 0
            var didFail = false

            loop: while !Task.isCancelled {
                cycle += 1
                for (index, step) in plan.steps.enumerated() {
                    if Task.isCancelled { break loop }
                    do {
                        _ = try await performClick(windowID: window.id, point: step.point, mode: mode)
                        totalClicks += 1
                        statusMessage = "第 \(cycle) 轮 · 第 \(index + 1)/\(plan.steps.count) 步已点击"
                        diagLog("flow click: cycle=\(cycle) step=\(index + 1)/\(plan.steps.count) point=(\(Int(step.point.x)),\(Int(step.point.y)))")
                    } catch is CancellationError {
                        break loop
                    } catch {
                        errorMessage = error.localizedDescription
                        didFail = true
                        break loop
                    }

                    // 最后一步的等待同样作用于轮次之间；整条流程的最后一步不再等待。
                    let isLastStep = index == plan.steps.count - 1
                    let isLastCycle = cycle >= plan.cycles
                    if !(isLastStep && isLastCycle) {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(step.randomInterval() * 1_000_000_000))
                        } catch {
                            break loop
                        }
                    }
                }
                if cycle >= plan.cycles { break }
            }

            let wasCancelled = Task.isCancelled
            flowTask = nil
            isWorking = false
            isRunningFlow = false
            diagLog("flow end: cancelled=\(wasCancelled) failed=\(didFail) cycles=\(cycle) clicks=\(totalClicks)")
            if wasCancelled {
                statusMessage = "已停止事件流：\(cycle) 轮、\(totalClicks) 次点击。"
            } else if didFail {
                statusMessage = "事件流已停止：\(cycle) 轮、\(totalClicks) 次点击。"
            } else {
                statusMessage = "事件流已完成：\(cycle) 轮、\(totalClicks) 次点击。"
            }
        }
    }

    func stopFlow() {
        guard flowTask != nil else { return }
        flowTask?.cancel()
        statusMessage = "正在停止事件流…"
    }

    // ⌃⌥Esc 全局紧急停止：不依赖鼠标、不依赖本应用是否在前台。
    private func installEmergencyHotkey() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleEmergencyKey(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleEmergencyKey(event) else { return event }
            return nil
        }
    }

    private func handleEmergencyKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == 53,
              modifiers.contains(.control),
              modifiers.contains(.option),
              !modifiers.contains(.command),
              !modifiers.contains(.shift) else {
            return false
        }
        guard isRepeating || isRunningFlow else { return false }
        if isRepeating { stopRepeating() }
        if isRunningFlow { stopFlow() }
        statusMessage = "已通过 ⌃⌥Esc 紧急停止。"
        return true
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

    private func validatedWindow() -> WindowDescriptor? {
        guard let selectedWindowID,
              let window = windowService.window(withID: selectedWindowID) else {
            errorMessage = ClickError.targetWindowUnavailable.localizedDescription
            refreshWindows()
            return nil
        }
        return window
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
