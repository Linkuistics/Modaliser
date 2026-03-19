import Testing
import LispKit
@testable import Modaliser

@Suite("OverlayNotifier")
struct OverlayNotifierTests {

    // MARK: - Helpers

    private func makeSetup() throws -> (OverlayNotifier, MockOverlayPresenter, ModalStateMachine) {
        let registry = CommandTreeRegistry()
        registry.registerTree(for: .global, root:
            .group(GroupDefinition(
                key: "",
                label: "Global",
                children: [
                    "s": .command(CommandDefinition(key: "s", label: "Safari", action: .void)),
                    "f": .group(GroupDefinition(
                        key: "f",
                        label: "Find",
                        children: [
                            "a": .command(CommandDefinition(key: "a", label: "Apps", action: .void)),
                        ]
                    )),
                ]
            ))
        )
        registry.setLeaderKey(for: .global, keyCode: KeyCode.f18)

        let presenter = MockOverlayPresenter()
        let coordinator = OverlayCoordinator(presenter: presenter, showDelay: 0)
        let notifier = OverlayNotifier(coordinator: coordinator)
        let machine = ModalStateMachine(registry: registry)
        return (notifier, presenter, machine)
    }

    // MARK: - Activated

    @Test func activatedShowsOverlayWithRootContent() throws {
        let (notifier, presenter, machine) = try makeSetup()
        machine.enterLeader(mode: .global)

        notifier.activated(machine: machine)

        #expect(presenter.showCallCount == 1)
        #expect(presenter.lastShownContent?.header == "Global")
        #expect(presenter.lastShownContent?.entries.count == 2)
    }

    @Test func activatedDoesNothingWhenMachineIsIdle() throws {
        let (notifier, presenter, machine) = try makeSetup()

        notifier.activated(machine: machine)

        #expect(presenter.showCallCount == 0)
    }

    // MARK: - Navigated

    @Test func navigatedUpdatesOverlayContent() throws {
        let (notifier, presenter, machine) = try makeSetup()
        machine.enterLeader(mode: .global)
        notifier.activated(machine: machine)

        machine.handleKey("f") // navigate into Find group
        notifier.navigated(machine: machine)

        #expect(presenter.showCallCount == 2)
        #expect(presenter.lastShownContent?.header == "Global \u{203A} Find")
    }

    // MARK: - Deactivated

    @Test func deactivatedDismissesOverlay() throws {
        let (notifier, presenter, machine) = try makeSetup()
        machine.enterLeader(mode: .global)
        notifier.activated(machine: machine)

        notifier.deactivated()

        #expect(presenter.dismissCallCount == 1)
    }

    // MARK: - After step back

    @Test func afterStepBackNavigatesWhenStillActive() throws {
        let (notifier, presenter, machine) = try makeSetup()
        machine.enterLeader(mode: .global)
        notifier.activated(machine: machine)
        machine.handleKey("f") // navigate into Find

        machine.stepBack() // back to root, still active
        notifier.afterStepBack(machine: machine)

        #expect(presenter.showCallCount == 2) // activate + step back update
        #expect(presenter.lastShownContent?.header == "Global")
    }

    @Test func afterStepBackDeactivatesWhenMachineExited() throws {
        let (notifier, presenter, machine) = try makeSetup()
        machine.enterLeader(mode: .global)
        notifier.activated(machine: machine)

        machine.stepBack() // at root → exits modal entirely
        notifier.afterStepBack(machine: machine)

        #expect(presenter.dismissCallCount == 1)
    }
}
