import Testing
import LispKit
@testable import Modaliser

@Suite("OverlayContentBuilder")
struct OverlayContentBuilderTests {

    // MARK: - Helpers

    private func makeTestTree() -> CommandNode {
        .group(GroupDefinition(
            key: "",
            label: "Global",
            children: [
                "s": .command(CommandDefinition(key: "s", label: "Safari", action: .void)),
                "t": .command(CommandDefinition(key: "t", label: "Terminal", action: .void)),
                "f": .group(GroupDefinition(
                    key: "f",
                    label: "Find",
                    children: [
                        "a": .command(CommandDefinition(key: "a", label: "Apps", action: .void)),
                        "w": .selector(SelectorDefinition(
                            key: "w",
                            label: "Windows",
                            config: SelectorConfig(
                                prompt: nil, source: nil, onSelect: nil,
                                remember: nil, idField: nil, actions: [], fileRoots: nil
                            )
                        )),
                    ]
                )),
            ]
        ))
    }

    // MARK: - Nil cases

    @Test func returnsNilWhenNodeIsNil() {
        let builder = OverlayContentBuilder()
        let content = builder.buildContent(
            currentNode: nil,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )
        #expect(content == nil)
    }

    @Test func returnsNilWhenNodeIsCommand() {
        let builder = OverlayContentBuilder()
        let node = CommandNode.command(CommandDefinition(key: "s", label: "Safari", action: .void))
        let content = builder.buildContent(
            currentNode: node,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )
        #expect(content == nil)
    }

    // MARK: - Header

    @Test func headerShowsTreeLabelAtRoot() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )
        #expect(content?.header == "Global")
    }

    @Test func headerShowsBreadcrumbWhenNavigated() {
        let builder = OverlayContentBuilder()
        let findGroup = makeTestTree().child(forKey: "f")!
        let content = builder.buildContent(
            currentNode: findGroup,
            path: ["f"],
            mode: .global,
            treeLabel: "Global"
        )
        #expect(content?.header == "Global \u{203A} Find")
    }

    // MARK: - Entries

    @Test func entriesIncludeAllChildren() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )!
        #expect(content.entries.count == 3)
    }

    @Test func entriesAreSortedAlphabeticallyByKey() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )!
        let keys = content.entries.map(\.key)
        #expect(keys == ["f", "s", "t"])
    }

    @Test func commandEntryHasCommandStyle() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )!
        let safariEntry = content.entries.first(where: { $0.key == "s" })!
        #expect(safariEntry.style == .command)
        #expect(safariEntry.label == "Safari")
    }

    @Test func groupEntryHasGroupStyle() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )!
        let findEntry = content.entries.first(where: { $0.key == "f" })!
        #expect(findEntry.style == .group)
        #expect(findEntry.label == "Find")
    }

    @Test func selectorEntryHasSelectorStyle() {
        let builder = OverlayContentBuilder()
        let findGroup = makeTestTree().child(forKey: "f")!
        let content = builder.buildContent(
            currentNode: findGroup,
            path: ["f"],
            mode: .global,
            treeLabel: "Global"
        )!
        let windowsEntry = content.entries.first(where: { $0.key == "w" })!
        #expect(windowsEntry.style == .selector)
        #expect(windowsEntry.label == "Windows")
    }

    // MARK: - Header icon

    @Test func headerIconIsNilForGlobalMode() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .global,
            treeLabel: "Global"
        )!
        #expect(content.headerIcon == nil)
    }

    @Test func headerIconIsBundleIdForLocalMode() {
        let builder = OverlayContentBuilder()
        let tree = makeTestTree()
        let content = builder.buildContent(
            currentNode: tree,
            path: [],
            mode: .local,
            treeLabel: "Safari",
            headerIcon: "com.apple.Safari"
        )
        #expect(content?.headerIcon == "com.apple.Safari")
    }
}
