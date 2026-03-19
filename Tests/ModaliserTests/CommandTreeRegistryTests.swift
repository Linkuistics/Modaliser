import Testing
import LispKit
@testable import Modaliser

@Suite("CommandTreeRegistry")
struct CommandTreeRegistryTests {
    @Test func registerAndRetrieveGlobalTree() {
        let registry = CommandTreeRegistry()
        let tree = CommandNode.group(GroupDefinition(
            key: "",
            label: "Global",
            children: [
                "s": .command(CommandDefinition(key: "s", label: "Safari", action: .void))
            ]
        ))
        registry.registerTree(for: .global, root: tree)
        let retrieved = registry.tree(for: .global)
        #expect(retrieved?.label == "Global")
    }

    @Test func retrieveUnregisteredTreeReturnsNil() {
        let registry = CommandTreeRegistry()
        #expect(registry.tree(for: .global) == nil)
    }

    @Test func registerAppLocalTree() {
        let registry = CommandTreeRegistry()
        let tree = CommandNode.group(GroupDefinition(
            key: "",
            label: "Safari",
            children: [:]
        ))
        registry.registerTree(for: .appLocal("com.apple.Safari"), root: tree)
        let retrieved = registry.tree(for: .appLocal("com.apple.Safari"))
        #expect(retrieved?.label == "Safari")
    }

    @Test func differentAppTreesAreIndependent() {
        let registry = CommandTreeRegistry()
        let safariTree = CommandNode.group(GroupDefinition(
            key: "", label: "Safari", children: [:]
        ))
        let zedTree = CommandNode.group(GroupDefinition(
            key: "", label: "Zed", children: [:]
        ))
        registry.registerTree(for: .appLocal("com.apple.Safari"), root: safariTree)
        registry.registerTree(for: .appLocal("dev.zed.Zed"), root: zedTree)

        #expect(registry.tree(for: .appLocal("com.apple.Safari"))?.label == "Safari")
        #expect(registry.tree(for: .appLocal("dev.zed.Zed"))?.label == "Zed")
    }

    @Test func leaderKeyConfiguration() {
        let registry = CommandTreeRegistry()
        registry.setLeaderKey(for: .global, keyCode: KeyCode.f18)
        registry.setLeaderKey(for: .local, keyCode: KeyCode.f17)
        #expect(registry.leaderKey(for: .global) == KeyCode.f18)
        #expect(registry.leaderKey(for: .local) == KeyCode.f17)
    }
}
