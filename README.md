# Current

原生 macOS 窗口自动点击工具：支持保存多个任务，在选定窗口中执行单击、定时连点或事件流；提供前台稳定模式与后台窗口路由模式，可按兼容性或无感操作需求选择。

```text
选择窗口 → 十字准星选点 → 单击 / 定时连点
```

## 特性

- 枚举并选择 Mac 上现存的窗口，十字准星选点（坐标相对窗口左上角，Esc 取消）
- 单击、可配置间隔与次数的连点、随时停止
- **任务列表**：左侧新增、删除和切换任务；右侧通过「保存为任务 / 保存修改」显式保存完整配置，重启后自动恢复上次选中的任务
- **事件流**：在同一窗口内添加多个点击位置，每步可配置「点击后等待」的随机间隔范围（精确到 0.1 秒）；可开启「选点时同时点击」边操作边编排；整条流程按指定的正整数次数循环，随时停止（不提供无限循环）
- **运行保护**：全局 `⌃⌥Esc` 紧急停止（不依赖鼠标与前台应用）；循环次数必须有限，不提供无限循环；默认使用兼容性最好的前台模式
- 窗口移动后点击位置跟随窗口原点；窗口缩小导致选点越界、窗口关闭/最小化/离开当前桌面时自动停止
- 三种点击模式：
  - **窗口路由模式（推荐）**：无感。优先通过 Accessibility 直接 `AXPress` 目标控件，完全不产生鼠标事件；坐标处没有可按下控件时回退窗口路由合成点击
  - **前台模式（稳定）**：真实全局鼠标事件，兼容性最好，但会占用鼠标和焦点
  - **公开 PID 模式（对照）**：公开 API 基线，多数应用不会响应，仅用于对照
- 状态栏明确显示本次实际走的是 AX 直按、合成点击还是回退通道

## 工作原理

1. **AXPress 优先**（`AXWindowClicker.swift`）
   在目标窗口的 Accessibility 树中定位选点处最深的可按下元素并执行 `AXPress`。不产生鼠标事件，因此不会触发窗口置前。
   Chromium/Electron 默认不暴露网页内容树，首次点击时自动设置 `AXEnhancedUserInterface` + `AXManualAccessibility` 并等待其构建（约 180ms，之后每次 3~15ms）。

2. **窗口路由回退**（`WindowRoutedClickDriver.swift`）
   通过 SkyLight 私有字段 51（`CGWindowID`）让 WindowServer 把合成鼠标事件命中测试到指定后台窗口，并以 `CGEventPostToPid` 投递。
   目标事件的 `clickState` 必须为 0：任何非零值都会让被点应用调用 `orderFront` 把窗口抬到前面。代价是 Chromium 不再合成 `click` 事件（`mousedown`/`mouseup` 仍会投递），所以网页类目标优先走 AXPress。

3. **兜底恢复**（`WindowOrdering.swift`）
   若仍有窗口被抬前，点击前后对比层叠顺序，用 `AXRaise` 把原本在目标之上的窗口按序抬回（不激活应用、不改变 key 窗口）。

## 系统要求

- macOS 14+
- Xcode 15+，[XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 辅助功能（Accessibility）权限，用于读取窗口信息、AXPress 与事件注入

## 构建与运行

在项目根目录执行：

```bash
xcodegen generate
xcodebuild -quiet test \
  -project Current.xcodeproj \
  -scheme Current \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData
open build/DerivedData/Build/Products/Debug/Current.app
```

## 权限说明

- 首次运行需在「系统设置 → 隐私与安全性 → 辅助功能」中授权 Current。
- 工程使用固定的 Apple Development 证书签名；Bundle ID 保留为 `com.h2ocean.WindowClicker`，以便延续已有授权（TCC 按 Bundle ID + 签名标识记录）。如需更换 Bundle ID，需要在授权列表中删除旧条目后重新授权。
- 若重新构建后权限异常：退出应用，删除辅助功能列表中的旧条目，重新打开应用并授权。

## 已知限制

- 锁屏后 WindowServer 会丢弃全部合成事件（屏幕保护但未锁屏不受影响）。
- 自绘界面、游戏等没有 AX 控件的目标只能走回退合成点击：不携带点击计数，依赖 `click` 事件的控件可能不响应。
- 多桌面 Spaces 与多显示器共享鼠标、键盘和前台焦点。
- 依赖的私有符号与字段没有 Apple 官方契约，macOS 升级后需要复测。
- 不做厂商适配；目标程序无需任何脚本或自动化接口。

## 目录结构

```text
Sources/
  CurrentApp.swift             应用入口
  AppModel.swift               界面状态、单击/连点/事件流/取消、z-order 恢复调度
  ContentView.swift            主界面
  FlowConfiguration.swift      事件流步骤模型与校验
  TaskConfiguration.swift      任务快照、窗口匹配与任务库
  TaskStore.swift              任务 JSON 本地持久化
  PickerController.swift       透明十字准星选点面板
  ClickEngine.swift            模式分发与回退
  ClickDriver.swift            驱动协议、投递通道、公共鼠标事件
  AXWindowClicker.swift        AX 树定位 + AXPress（无感点击）
  WindowRoutedClickDriver.swift 窗口路由合成点击
  ForegroundClickDriver.swift  前台全局事件
  PublicPIDClickDriver.swift   公开 PID 基线
  FocusWithoutRaise.swift      focus-without-raise 事件记录
  WindowOrdering.swift         用 AXRaise 恢复窗口层叠顺序
  WindowService.swift          窗口枚举与描述
  WindowGeometry.swift         坐标换算
Tests/
  WindowGeometryTests.swift    坐标换算测试
  RepeatConfigurationTests.swift 连点参数测试
  FlowConfigurationTests.swift  事件流校验测试
```

## 参考

- [NSExceptional/winctl](https://github.com/NSExceptional/winctl) —— `research/hittest` 的窗口路由消融实验
- [trycua/cua](https://github.com/trycua/cua) —— cua-driver 的后台点击与 key_focus_guard
- [koekeishiya/yabai](https://github.com/koekeishiya/yabai) —— focus-without-raise 配方
