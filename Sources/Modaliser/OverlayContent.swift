/// Complete content for the which-key overlay display.
/// Built from the modal state machine's current position in the command tree.
struct OverlayContent {
    /// Header text showing the navigation breadcrumb (e.g. "Global > Find").
    let header: String
    /// Bundle identifier for an app icon in the header (used in local/app-specific mode).
    let headerIcon: String?
    /// Available keybinding entries at the current tree position, sorted by key.
    let entries: [OverlayEntry]
}
