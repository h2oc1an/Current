import AppKit
import CoreGraphics

enum PointPickerResult {
    case picked(CGPoint)
    case cancelled
    case failed(String)
}

@MainActor
final class PointPickerController: NSObject {
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var presentationTask: Task<Void, Never>?
    private var completion: ((PointPickerResult) -> Void)?

    func present(for window: WindowDescriptor, completion: @escaping (PointPickerResult) -> Void) {
        self.completion = completion
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID) else {
            finish(.failed(ClickError.applicationActivationFailed.localizedDescription))
            return
        }
        _ = application.activate(options: [.activateAllWindows])
        diagLog("picker present: target=\(window.ownerPID) front=\(frontDesc())")

        presentationTask = Task { [weak self] in
            guard let self else { return }
            // 首次 activate 偶尔不生效或来不及完成（macOS 激活时序），
            // 轮询确认目标成为前台应用，中途重试一次，超时仍显示选择器兜底。
            // 注意应用激活 ≠ 窗口置前，activateAllWindows 才能覆盖"已激活但窗口被遮挡"。
            for attempt in 0..<10 {
                if Task.isCancelled { return }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                diagLog("picker poll \(attempt): front=\(frontDesc())")
                if front == window.ownerPID { break }
                if attempt == 2 {
                    let ok = application.activate(options: [.activateAllWindows])
                    diagLog("picker retry activate returned \(ok)")
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            guard !Task.isCancelled else { return }
            // frontmost 确认后再给窗口 raise 留一点时间（已激活应用的窗口置前是异步的）。
            try? await Task.sleep(nanoseconds: 150_000_000)
            diagLog("picker showPanel: front=\(frontDesc())")
            showPanel(for: window)
        }
    }

    private func showPanel(for window: WindowDescriptor) {
        guard let latestWindow = WindowService().window(withID: window.id) else {
            finish(.failed(ClickError.targetWindowUnavailable.localizedDescription))
            return
        }
        guard let mainScreenHeight = NSScreen.screens.first?.frame.height, mainScreenHeight > 0 else {
            finish(.failed("无法读取显示器坐标。"))
            return
        }

        presentationTask = nil
        let frame = WindowGeometry.appKitFrame(
            forQuartzRect: latestWindow.bounds,
            mainScreenHeight: mainScreenHeight
        )
        let pickerView = CrosshairView(frame: NSRect(origin: .zero, size: frame.size))
        pickerView.onPick = { [weak self] point in
            self?.finish(.picked(point))
        }

        let panel = PickerPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = pickerView
        self.panel = panel

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.finish(.cancelled)
            return nil
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func finish(_ result: PointPickerResult) {
        presentationTask?.cancel()
        presentationTask = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil

        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CrosshairView: NSView {
    var onPick: ((CGPoint) -> Void)?
    private var mouseLocation: CGPoint?
    private var trackingAreaRef: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouseLocation = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onPick?(WindowGeometry.relativePoint(forAppKitPoint: point, inAppKitFrame: bounds))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()

        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
        border.stroke()

        if let point = mouseLocation, bounds.contains(point) {
            let crosshair = NSBezierPath()
            crosshair.move(to: CGPoint(x: 0, y: point.y))
            crosshair.line(to: CGPoint(x: bounds.width, y: point.y))
            crosshair.move(to: CGPoint(x: point.x, y: 0))
            crosshair.line(to: CGPoint(x: point.x, y: bounds.height))
            crosshair.lineWidth = 1
            NSColor.systemYellow.setStroke()
            crosshair.stroke()

            NSColor.systemYellow.setFill()
            NSBezierPath(ovalIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
        }

        drawInstructions()
    }

    private func drawInstructions() {
        let text = "单击选点 · Esc 取消" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = text.size(withAttributes: attributes)
        let backgroundRect = CGRect(
            x: (bounds.width - textSize.width - 20) / 2,
            y: 14,
            width: textSize.width + 20,
            height: textSize.height + 10
        )
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: backgroundRect.minX + 10, y: backgroundRect.minY + 5), withAttributes: attributes)
    }
}
