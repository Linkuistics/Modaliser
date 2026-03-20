import AppKit

/// Provides the bundle identifier of the currently focused application.
/// Used by the modal state machine to look up app-local command trees.
struct FocusedAppObserver {

    /// The bundle identifier of the frontmost application, or nil if unavailable.
    var currentBundleId: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
