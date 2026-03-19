/// Builds overlay display content from the modal state machine's current state.
/// Pure data transformation — no UI, no side effects.
struct OverlayContentBuilder {

    /// Build overlay content from the current modal navigation state.
    /// Returns nil if the node is not a group (overlay only shows for groups).
    func buildContent(
        currentNode: CommandNode?,
        path: [String],
        mode: LeaderMode?,
        treeLabel: String,
        headerIcon: String? = nil
    ) -> OverlayContent? {
        guard let node = currentNode, case .group(let def) = node else {
            return nil
        }

        let header = buildHeader(treeLabel: treeLabel, currentGroupLabel: def.label, path: path)
        let entries = buildEntries(from: def.children)

        return OverlayContent(
            header: header,
            headerIcon: headerIcon,
            entries: entries
        )
    }

    // MARK: - Private

    private func buildHeader(treeLabel: String, currentGroupLabel: String, path: [String]) -> String {
        if path.isEmpty {
            return treeLabel
        }
        return treeLabel + " \u{203A} " + currentGroupLabel
    }

    private func buildEntries(from children: [String: CommandNode]) -> [OverlayEntry] {
        children.values
            .map { node in
                OverlayEntry(
                    key: node.key,
                    label: node.label,
                    style: entryStyle(for: node)
                )
            }
            .sorted { $0.key < $1.key }
    }

    private func entryStyle(for node: CommandNode) -> OverlayEntryStyle {
        switch node {
        case .command: .command
        case .group: .group
        case .selector: .selector
        }
    }
}
