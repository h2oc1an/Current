import CoreGraphics
import Foundation

// focus-without-raise（配方源自 yabai / cua-driver）：向目标进程发送 248 字节
// focus event record，使目标窗口成为 AppKit-key，但不 raise、不改变窗口层级。
// 随后的合成 mouseDown 到达时窗口已是 key，不会再触发"点击激活并置前"。
//
// 只向目标发 focus record，不向当前前台进程发 defocus record——cua 实测
// defocus 会让用户的 key 窗口失去键盘输入，且重新激活也无法恢复。
struct FocusWithoutRaise {
    private typealias PostEventRecordTo = @convention(c) (UnsafeRawPointer, UnsafePointer<UInt8>) -> Int32
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias GetWindowOwner = @convention(c) (Int32, UInt32, UnsafeMutablePointer<Int32>) -> Int32
    private typealias GetConnectionPSN = @convention(c) (Int32, UnsafeMutableRawPointer) -> Int32
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32

    private let postEventRecord: PostEventRecordTo?
    private let mainConnectionID: MainConnectionID?
    private let getWindowOwner: GetWindowOwner?
    private let getConnectionPSN: GetConnectionPSN?
    private let getProcessForPID: GetProcessForPID?

    init() {
        postEventRecord = Self.resolve("SLPSPostEventRecordTo")
        mainConnectionID = Self.resolve("CGSMainConnectionID")
        getWindowOwner = Self.resolve("SLSGetWindowOwner")
        getConnectionPSN = Self.resolve("SLSGetConnectionPSN")
        getProcessForPID = Self.resolve("GetProcessForPID")
    }

    private static func resolve<T>(_ name: String) -> T? {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let symbol = dlsym(handle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    // best-effort：符号缺失或投递失败返回 false，调用方继续发点击（只是可能置前）。
    func apply(to window: WindowDescriptor) -> Bool {
        guard let postEventRecord else { return false }
        var psn = [UInt8](repeating: 0, count: 8)
        guard resolvePSN(for: window, into: &psn) else { return false }

        var record = [UInt8](repeating: 0, count: 0xF8)
        record[0x04] = 0xF8
        record[0x08] = 0x0D
        let wid = window.id
        record[0x3C] = UInt8(wid & 0xFF)          // 目标 CGWindowID，小端
        record[0x3D] = UInt8((wid >> 8) & 0xFF)
        record[0x3E] = UInt8((wid >> 16) & 0xFF)
        record[0x3F] = UInt8((wid >> 24) & 0xFF)
        record[0x8A] = 0x01                        // 0x01=focus，0x02=defocus

        return psn.withUnsafeBytes { psnPointer in
            postEventRecord(psnPointer.baseAddress!, record) == 0
        }
    }

    private func resolvePSN(for window: WindowDescriptor, into psn: inout [UInt8]) -> Bool {
        if let mainConnectionID, let getWindowOwner, let getConnectionPSN {
            let connection = mainConnectionID()
            var ownerConnection: Int32 = 0
            if getWindowOwner(connection, window.id, &ownerConnection) == 0, ownerConnection != 0 {
                let resolved = psn.withUnsafeMutableBytes { pointer in
                    getConnectionPSN(ownerConnection, pointer.baseAddress!) == 0
                }
                if resolved { return true }
            }
        }
        if let getProcessForPID {
            return psn.withUnsafeMutableBytes { pointer in
                getProcessForPID(window.ownerPID, pointer.baseAddress!) == 0
            }
        }
        return false
    }
}
