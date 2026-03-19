import Testing
import LispKit
@testable import Modaliser

@Suite("CommandNode")
struct CommandNodeTests {
    @Test func commandNodeStoresKeyAndLabel() {
        let node = CommandNode.command(CommandDefinition(
            key: "s",
            label: "Safari",
            action: .void
        ))
        #expect(node.key == "s")
        #expect(node.label == "Safari")
    }

    @Test func groupNodeStoresKeyLabelAndChildren() {
        let child = CommandNode.command(CommandDefinition(
            key: "s",
            label: "Safari",
            action: .void
        ))
        let group = CommandNode.group(GroupDefinition(
            key: "f",
            label: "Find",
            children: ["s": child]
        ))
        #expect(group.key == "f")
        #expect(group.label == "Find")
    }

    @Test func groupNodeChildLookupByKey() {
        let child = CommandNode.command(CommandDefinition(
            key: "s",
            label: "Safari",
            action: .void
        ))
        let group = CommandNode.group(GroupDefinition(
            key: "f",
            label: "Find",
            children: ["s": child]
        ))
        let found = group.child(forKey: "s")
        #expect(found?.key == "s")
        #expect(found?.label == "Safari")
    }

    @Test func groupNodeChildLookupReturnsNilForMissingKey() {
        let group = CommandNode.group(GroupDefinition(
            key: "f",
            label: "Find",
            children: [:]
        ))
        #expect(group.child(forKey: "x") == nil)
    }

    @Test func selectorNodeStoresConfig() {
        let config = SelectorConfig(
            prompt: "Find app…",
            source: .void,
            onSelect: .void,
            remember: "apps",
            idField: "bundleId",
            actions: [],
            fileRoots: nil
        )
        let node = CommandNode.selector(SelectorDefinition(
            key: "a",
            label: "Find Apps",
            config: config
        ))
        #expect(node.key == "a")
        #expect(node.label == "Find Apps")
    }

    @Test func commandNodeIsCommandReturnsTrue() {
        let node = CommandNode.command(CommandDefinition(
            key: "s",
            label: "Safari",
            action: .void
        ))
        #expect(node.isCommand)
        #expect(!node.isGroup)
        #expect(!node.isSelector)
    }

    @Test func groupNodeIsGroupReturnsTrue() {
        let node = CommandNode.group(GroupDefinition(
            key: "f",
            label: "Find",
            children: [:]
        ))
        #expect(node.isGroup)
        #expect(!node.isCommand)
        #expect(!node.isSelector)
    }

    @Test func actionConfigStoresNameAndTrigger() {
        let action = ActionConfig(
            name: "Open",
            description: "Launch the app",
            trigger: .primary,
            run: .void
        )
        #expect(action.name == "Open")
        #expect(action.description == "Launch the app")
        #expect(action.trigger == .primary)
    }
}
