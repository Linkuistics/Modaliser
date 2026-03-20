import ServiceManagement

/// Manages the "launch at login" setting using SMAppService (macOS 13+).
enum LaunchAtLogin {

    /// Whether the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggle the launch-at-login setting.
    static func toggle() {
        if isEnabled {
            try? SMAppService.mainApp.unregister()
        } else {
            try? SMAppService.mainApp.register()
        }
    }
}
