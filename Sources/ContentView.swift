import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            taskSidebar
            Divider()
            if model.showsConfiguration {
                ScrollView {
                    configurationPanel
                }
                .frame(width: 640, height: 680)
                .overlay(alignment: .bottomTrailing) {
                    Button(model.selectedTaskID == nil ? "保存为任务" : "保存修改") {
                        model.saveTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                    .shadow(radius: 4, y: 2)
                    .padding(20)
                }
            } else {
                VStack(spacing: 24) {
                    Image("HomeLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300)
                        .opacity(0.3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text("未选择任务")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                        Text("从左侧选择任务，或点击“新增”创建任务。")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 640, height: 680)
            }
        }
        .frame(height: 680)
    }

    private var taskSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("任务")
                .font(.title2.bold())

            HStack {
                Button {
                    model.startNewTask()
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .disabled(model.isWorking)

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(model.selectedTaskID == nil || model.isWorking)
            }

            List(model.tasks) { task in
                let isSelected = model.selectedTaskID == task.id
                Button {
                    model.selectTask(id: task.id)
                } label: {
                    Text(task.name)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .padding(.horizontal, 12)
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(model.isWorking)
            .overlay {
                if model.tasks.isEmpty {
                    Text("暂无任务\n点击“新增”开始配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(12)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .confirmationDialog("删除选中的任务？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                model.deleteSelectedTask()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("任务配置将被永久删除。")
        }
    }

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Current")
                    .font(.title2.bold())
                Spacer()
                Button("刷新窗口") {
                    model.refreshWindows()
                }
                .disabled(model.isWorking)
            }

            HStack {
                Text("任务名称")
                TextField("任务名称", text: $model.taskNameText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isWorking)
            }

            GroupBox("1. 选择窗口") {
                List(model.windows, selection: $model.selectedWindowID) { window in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(window.displayTitle)
                            .lineLimit(1)
                        Text("\(Int(window.bounds.width)) × \(Int(window.bounds.height)) · PID \(window.ownerPID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(window.id)
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .disabled(model.isWorking)
                .overlay {
                    if model.windows.isEmpty {
                        Text("没有可选择的窗口，请点击“刷新窗口”")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .groupBoxStyle(RoundedGroupBoxStyle())

            GroupBox("2. 执行点击") {
                VStack(alignment: .leading, spacing: 12) {
                    modePicker

                    Divider()

                    Picker("执行方式", selection: $model.executionMode) {
                        Text("单点").tag(ExecutionMode.single)
                        Text("事件流").tag(ExecutionMode.flow)
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.isWorking)

                    Group {
                        if model.executionMode == .single {
                            singlePanel
                        } else {
                            flowPanel
                        }
                    }
                    .frame(minHeight: 240, alignment: .topLeading)

                    if model.isWorking && (model.isRepeating || model.isRunningFlow) {
                        Text("运行中：按 Control + Option + Esc（⌃⌥Esc）跳出循环。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .groupBoxStyle(RoundedGroupBoxStyle())

            VStack(alignment: .leading, spacing: 5) {
                if let status = model.statusMessage {
                    Text(status)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("打开辅助功能设置") {
                    model.openAccessibilitySettings()
                }
                .font(.caption)
                Spacer()
                Text("最小化或其他桌面的窗口不支持点击")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        // 只固定宽度，高度随内容自适应；固定高度会让内容上下溢出并被裁切。
        .frame(width: 640)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("点击模式", selection: $model.clickMode) {
                ForEach(ClickMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .disabled(model.isWorking)

            switch model.clickMode {
            case .windowRouted:
                Text("不切换窗口、不占用鼠标、不置前；优先通过辅助功能直接按下目标控件，坐标处无可按控件时回退合成点击。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .publicPID:
                Text("不切换窗口、不占用鼠标；公开 API 基线，多数应用不会响应，仅用于对照。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .foreground:
                Text("点击前会将目标应用置前，操作期间会占用鼠标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var singlePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("选取位置") {
                    model.choosePoint()
                }
                .disabled(model.selectedWindow == nil || model.isWorking)

                if let point = model.selectedRelativePoint {
                    Text("X \(Int(point.x))，Y \(Int(point.y))（相对窗口左上角）")
                        .foregroundStyle(.secondary)
                } else {
                    Text("尚未选点")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Button("单击一次") {
                    Task { await model.performSingleClick() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedRelativePoint == nil || model.isWorking)

                if model.isWorking && !model.isRepeating {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Spacer()
            }

            Divider()

            HStack {
                Text("每")
                TextField("间隔", text: $model.intervalText)
                    .frame(width: 65)
                    .disabled(model.isWorking)
                Text("秒点击一次，共")
                TextField("次数", text: $model.countText)
                    .frame(width: 65)
                    .disabled(model.isWorking)
                Text("次")
                Spacer()
            }

            HStack {
                Button("开始连点") {
                    model.startRepeating()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedRelativePoint == nil || model.isWorking)

                Button("停止", role: .destructive) {
                    model.stopRepeating()
                }
                .disabled(!model.isRepeating)

                if model.isRepeating {
                    Text("已发送 \(model.completedCount) 次")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var flowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 8) {
                        Text("第 \(index + 1) 步")
                            .monospacedDigit()
                        Text("X \(Int(step.point.x))，Y \(Int(step.point.y))")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("间隔")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("最小", text: stepMinimumIntervalBinding(id: step.id))
                            .multilineTextAlignment(.center)
                            .frame(width: 44)
                            .disabled(model.isWorking)
                        Text("到")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("最大", text: stepMaximumIntervalBinding(id: step.id))
                            .multilineTextAlignment(.center)
                            .frame(width: 44)
                            .disabled(model.isWorking)
                        Text("秒")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("重新选点") {
                            model.repickStep(id: step.id)
                        }
                        .disabled(model.isWorking)
                        Button {
                            model.removeStep(id: step.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isWorking)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(model.isWorking)
            .overlay {
                if model.steps.isEmpty {
                    Text("还没有步骤，点击“添加步骤”后在目标窗口中选点")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("添加步骤") {
                    model.addStep()
                }
                .disabled(model.selectedWindow == nil || model.isWorking)

                Spacer()

                Text("循环次数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("次数", text: $model.flowCycleText)
                    .frame(width: 60)
                    .disabled(model.isWorking)
                Text("次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("开始事件流") {
                    model.startFlow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.steps.isEmpty || model.isWorking)

                Button("停止", role: .destructive) {
                    model.stopFlow()
                }
                .disabled(!model.isRunningFlow)

                if model.isRunningFlow {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Spacer()
            }
        }
    }

    private func stepMinimumIntervalBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { model.steps.first(where: { $0.id == id })?.minimumIntervalText ?? "" },
            set: { model.updateStepMinimumInterval(id: id, text: $0) }
        )
    }

    private func stepMaximumIntervalBinding(id: UUID) -> Binding<String> {
        Binding(
            get: { model.steps.first(where: { $0.id == id })?.maximumIntervalText ?? "" },
            set: { model.updateStepMaximumInterval(id: id, text: $0) }
        )
    }
}

private struct RoundedGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }
}