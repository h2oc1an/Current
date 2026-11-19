import CoreGraphics
import Foundation

struct WindowDescriptor: Hashable, Identifiable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    var displayTitle: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanTitle.isEmpty ? "\(ownerName) — 窗口 \(id)" : "\(ownerName) — \(cleanTitle)"
    }
}

struct WindowService {
    // CGWindowList 返回顺序即 z-order（front-to-back）。
    // 包含本应用自己的窗口：恢复 z-order 时需要知道自己原本在目标的上面还是下面。
    func zOrderedWindows() -> [WindowDescriptor] {
        rawWindows(includeOwnWindows: true)
    }

    func visibleWindows() -> [WindowDescriptor] {
        rawWindows().sorted {
            if $0.ownerName == $1.ownerName {
                return $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending
            }
            return $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending
        }
    }

    private func rawWindows(includeOwnWindows: Bool = false) -> [WindowDescriptor] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let items = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = getpid()

        return items.compactMap { item in
            guard let number = item[kCGWindowNumber as String] as? NSNumber,
                  let ownerNumber = item[kCGWindowOwnerPID as String] as? NSNumber,
                  let layer = item[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  includeOwnWindows || ownerNumber.int32Value != ownPID,
                  let isOnscreen = item[kCGWindowIsOnscreen as String] as? Bool,
                  isOnscreen,
                  let boundsInfo = item[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 50,
                  bounds.height >= 50 else {
                return nil
            }

            let ownerName = item[kCGWindowOwnerName as String] as? String ?? "未知应用"
            let title = item[kCGWindowName as String] as? String ?? ""
            return WindowDescriptor(
                id: number.uint32Value,
                ownerPID: ownerNumber.int32Value,
                ownerName: ownerName,
                title: title,
                bounds: bounds
            )
        }
    }

    func window(withID id: CGWindowID) -> WindowDescriptor? {
        visibleWindows().first { $0.id == id }
    }
}
