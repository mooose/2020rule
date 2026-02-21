import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case unsupportedOS
    case failedToUpdate(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Launch at login requires macOS 13 or newer"
        case .failedToUpdate(let message):
            return message
        }
    }
}

final class LaunchAtLoginManager {
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LaunchAtLoginError.unsupportedOS
        }

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            throw LaunchAtLoginError.failedToUpdate(error.localizedDescription)
        }
    }
}
