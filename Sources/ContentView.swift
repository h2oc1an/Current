import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
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
                .frame(height: 165)
                .disabled(model.isWorking)
                .overlay {
                    if model.windows.isEmpty {
                        Text("没有可选择的窗口，请点击“刷新窗口”")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GroupBox("2. 选择点击位置") {
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
            }

            GroupBox("3. 执行点击") {
                VStack(alignment: .leading, spacing: 12) {
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
                    }
                }
            }

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
}
