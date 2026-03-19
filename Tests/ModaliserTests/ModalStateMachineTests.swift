import Testing
import LispKit
@testable import Modaliser

@Suite("ModalStateMachine")
struct ModalStateMachineTests {

    // MARK: - Helpers

    /// Create a registry with a simple global tree and leader keys configured.
    private func makeRegistryWithGlobalTree() -> CommandTreeRegistry {
        let registry = CommandTreeRegistry()
        registry.setLeaderKey(for: .global, keyCode: KeyCode.f18)
        registry.setLeaderKey(for: .local, keyCode: KeyCode.f17)

        let tree = CommandNode.group(GroupDefinition(
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
                                prompt: "Select window…",
                                source: .void,
                                onSelect: .void,
                                remember: nil,
                                idField: nil,
                                actions: [],
                                fileRoots: nil
                            )
                        ))
                    ]
                ))
            ]
        ))
        registry.registerTree(for: .global, root: tree)
        return registry
    }

    // MARK: - Initial state

    @Test func initialStateIsIdle() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        #expect(machine.isIdle)
        #expect(!machine.isActive)
    }

    // MARK: - Enter leader

    @Test func enterLeaderActivatesModal() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        #expect(machine.isActive)
        #expect(!machine.isIdle)
    }

    @Test func enterLeaderSetsMode() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        #expect(machine.currentMode == .global)
    }

    @Test func enterLeaderSetsCurrentNodeToRoot() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        #expect(machine.currentNode?.label == "Global")
    }

    @Test func enterLeaderStartsWithEmptyPath() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        #expect(machine.path.isEmpty)
    }

    @Test func enterLeaderWithNoTreeStaysIdle() {
        let registry = CommandTreeRegistry()
        registry.setLeaderKey(for: .global, keyCode: KeyCode.f18)
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        #expect(machine.isIdle)
    }

    // MARK: - Exit leader

    @Test func exitLeaderReturnsToIdle() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        machine.exitLeader()
        #expect(machine.isIdle)
        #expect(machine.currentNode == nil)
        #expect(machine.path.isEmpty)
    }

    @Test func exitLeaderWhenAlreadyIdleIsNoop() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.exitLeader()
        #expect(machine.isIdle)
    }

    // MARK: - Navigate into group

    @Test func navigateIntoGroupDescends() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        let result = machine.handleKey("f")
        #expect(result == .navigated)
        #expect(machine.currentNode?.label == "Find")
        #expect(machine.path == ["f"])
        #expect(machine.isActive)
    }

    // MARK: - Execute command

    @Test func navigateToCommandExecutesAndExits() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        let result = machine.handleKey("s")
        #expect(result == .executed(.void))
        #expect(machine.isIdle)
    }

    @Test func navigateToCommandInGroupExecutesAndExits() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        _ = machine.handleKey("f")
        let result = machine.handleKey("a")
        #expect(result == .executed(.void))
        #expect(machine.isIdle)
    }

    // MARK: - Selector

    @Test func navigateToSelectorReportsSelector() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        _ = machine.handleKey("f")
        let result = machine.handleKey("w")
        if case .openSelector(let def) = result {
            #expect(def.label == "Windows")
        } else {
            #expect(Bool(false), "Expected openSelector, got \(result)")
        }
        // Modal exits when selector is opened (chooser takes over)
        #expect(machine.isIdle)
    }

    // MARK: - Unknown key

    @Test func unknownKeyReturnsNoBinding() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        let result = machine.handleKey("z")
        #expect(result == .noBinding("z"))
        // Exit after unknown key (matches Hammerspoon behavior)
        #expect(machine.isIdle)
    }

    // MARK: - Step back

    @Test func stepBackReturnsToParent() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        _ = machine.handleKey("f")
        #expect(machine.currentNode?.label == "Find")
        machine.stepBack()
        #expect(machine.currentNode?.label == "Global")
        #expect(machine.path.isEmpty)
        #expect(machine.isActive)
    }

    @Test func stepBackAtRootExitsModal() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        machine.stepBack()
        #expect(machine.isIdle)
    }

    // MARK: - Path tracking

    @Test func pathTracksNavigationDepth() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        _ = machine.handleKey("f")
        #expect(machine.path == ["f"])
    }

    // MARK: - Available children

    @Test func availableChildrenReturnsCurrentGroupChildren() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        let children = machine.availableChildren
        #expect(children.count == 3)
        #expect(children.contains(where: { $0.key == "s" }))
        #expect(children.contains(where: { $0.key == "t" }))
        #expect(children.contains(where: { $0.key == "f" }))
    }

    @Test func availableChildrenAfterNavigationShowsSubgroupChildren() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        machine.enterLeader(mode: .global)
        _ = machine.handleKey("f")
        let children = machine.availableChildren
        #expect(children.count == 2)
        #expect(children.contains(where: { $0.key == "a" }))
        #expect(children.contains(where: { $0.key == "w" }))
    }

    @Test func availableChildrenWhenIdleIsEmpty() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        #expect(machine.availableChildren.isEmpty)
    }

    // MARK: - Handle key when idle

    @Test func handleKeyWhenIdleReturnsNoBinding() {
        let registry = makeRegistryWithGlobalTree()
        let machine = ModalStateMachine(registry: registry)
        let result = machine.handleKey("s")
        #expect(result == .noBinding("s"))
        #expect(machine.isIdle)
    }
}
