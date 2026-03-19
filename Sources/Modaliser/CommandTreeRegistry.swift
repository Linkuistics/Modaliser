import CoreGraphics

/// Identifies which command tree to look up.
enum TreeScope: Hashable {
    /// The global command tree (triggered by global leader key).
    case global
    /// An app-specific command tree, keyed by bundle identifier.
    case appLocal(String)
}

/// Identifies the leader key mode for configuration.
enum LeaderMode: Hashable {
    case global
    case local
}

/// Stores registered command trees, leader key configuration, and theme.
/// Populated by evaluating the Scheme config, read by the modal state machine and overlay.
final class CommandTreeRegistry {
    private var trees: [TreeScope: CommandNode] = [:]
    private var leaderKeys: [LeaderMode: CGKeyCode] = [:]
    var theme: OverlayTheme?

    func registerTree(for scope: TreeScope, root: CommandNode) {
        trees[scope] = root
    }

    func tree(for scope: TreeScope) -> CommandNode? {
        trees[scope]
    }

    func setLeaderKey(for mode: LeaderMode, keyCode: CGKeyCode) {
        leaderKeys[mode] = keyCode
    }

    func leaderKey(for mode: LeaderMode) -> CGKeyCode? {
        leaderKeys[mode]
    }
}
