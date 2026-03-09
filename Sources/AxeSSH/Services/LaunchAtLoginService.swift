import Foundation
import ServiceManagement

enum LaunchAtLoginService {
    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        }
    }
}
