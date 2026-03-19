import CoreGraphics

/// Tracks modal navigation state: which tree is active, current position, and breadcrumb path.
/// Pure logic — no UI, no keyboard, no side effects. The caller acts on the results.
final class ModalStateMachine {
    private let registry: CommandTreeRegistry
    private var rootNode: CommandNode?
    private var currentNodeInternal: CommandNode?
    private var currentModeInternal: LeaderMode?
    private var pathInternal: [String] = []

    init(registry: CommandTreeRegistry) {
        self.registry = registry
    }

    // MARK: - Public state

    var isIdle: Bool { currentNodeInternal == nil }
    var isActive: Bool { !isIdle }
    var currentMode: LeaderMode? { currentModeInternal }
    var currentNode: CommandNode? { currentNodeInternal }
    var path: [String] { pathInternal }

    /// The children available at the current position (for overlay display).
    var availableChildren: [CommandNode] {
        guard let node = currentNodeInternal, case .group(let def) = node else {
            return []
        }
        return Array(def.children.values)
    }

    // MARK: - State transitions

    /// Enter modal mode for the given leader mode (global or local).
    /// Looks up the corresponding tree in the registry.
    func enterLeader(mode: LeaderMode) {
        let scope: TreeScope = (mode == .global) ? .global : .appLocal("")
        guard let tree = registry.tree(for: scope) else { return }
        rootNode = tree
        currentNodeInternal = tree
        currentModeInternal = mode
        pathInternal = []
    }

    /// Exit modal mode, resetting all state.
    func exitLeader() {
        rootNode = nil
        currentNodeInternal = nil
        currentModeInternal = nil
        pathInternal = []
    }

    /// Handle a key press while modal is active.
    /// Returns the result of the dispatch (navigate, execute, open selector, or no binding).
    @discardableResult
    func handleKey(_ key: String) -> KeyDispatchResult {
        guard let node = currentNodeInternal else { return .noBinding(key) }

        guard let child = node.child(forKey: key) else {
            exitLeader()
            return .noBinding(key)
        }

        switch child {
        case .group:
            currentNodeInternal = child
            pathInternal.append(key)
            return .navigated

        case .command(let def):
            let action = def.action
            exitLeader()
            return .executed(action)

        case .selector(let def):
            exitLeader()
            return .openSelector(def)
        }
    }

    /// Step back one level in the navigation path.
    /// If already at root, exits modal entirely.
    func stepBack() {
        guard isActive else { return }

        if pathInternal.isEmpty {
            exitLeader()
            return
        }

        pathInternal.removeLast()
        // Rebuild current node by walking path from root
        currentNodeInternal = rebuildCurrentNode()
    }

    // MARK: - Private

    /// Walk the path from root to reconstruct the current node.
    private func rebuildCurrentNode() -> CommandNode? {
        var node = rootNode
        for key in pathInternal {
            node = node?.child(forKey: key)
        }
        return node
    }
}
