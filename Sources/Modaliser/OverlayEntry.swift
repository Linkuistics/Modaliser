/// Style of a command entry in the which-key overlay.
enum OverlayEntryStyle: Equatable {
    case command
    case group
    case selector
}

/// A single entry in the which-key overlay, representing one available keybinding.
struct OverlayEntry: Equatable {
    let key: String
    let label: String
    let style: OverlayEntryStyle
}
