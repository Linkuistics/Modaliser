import Testing
import LispKit
@testable import Modaliser

@Suite("ChooserActionPanel")
struct ChooserActionPanelTests {

    private func makeDummyChoice() -> ChooserChoice {
        ChooserChoice(text: "Safari", subText: nil, icon: nil, iconType: nil, schemeValue: .null)
    }

    private func makeDummyActions() -> [ActionConfig] {
        [
            ActionConfig(name: "Open", description: nil, trigger: .primary, run: .null),
            ActionConfig(name: "Show in Finder", description: nil, trigger: .secondary, run: .null),
            ActionConfig(name: "Copy Path", description: nil, trigger: nil, run: .null),
        ]
    }

    // MARK: - Activation

    @Test func initialStateIsInactive() {
        let panel = ChooserActionPanel()
        #expect(!panel.isActive)
        #expect(panel.actions.isEmpty)
        #expect(panel.selectedChoice == nil)
    }

    @Test func activateSetsStateCorrectly() {
        let panel = ChooserActionPanel()
        let choice = makeDummyChoice()
        let actions = makeDummyActions()

        panel.activate(for: choice, actions: actions)

        #expect(panel.isActive)
        #expect(panel.actions.count == 3)
        #expect(panel.selectedChoice?.text == "Safari")
        #expect(panel.selectedIndex == 0)
    }

    @Test func deactivateResetsState() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())

        panel.deactivate()

        #expect(!panel.isActive)
        #expect(panel.actions.isEmpty)
        #expect(panel.selectedChoice == nil)
        #expect(panel.selectedIndex == 0)
    }

    // MARK: - Navigation

    @Test func moveDownIncrementsIndex() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())

        panel.moveDown()
        #expect(panel.selectedIndex == 1)

        panel.moveDown()
        #expect(panel.selectedIndex == 2)
    }

    @Test func moveDownClampsAtEnd() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())

        panel.moveDown()
        panel.moveDown()
        panel.moveDown() // beyond last
        #expect(panel.selectedIndex == 2)
    }

    @Test func moveUpDecrementsIndex() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())
        panel.moveDown()
        panel.moveDown()

        panel.moveUp()
        #expect(panel.selectedIndex == 1)
    }

    @Test func moveUpClampsAtStart() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())

        panel.moveUp() // already at 0
        #expect(panel.selectedIndex == 0)
    }

    // MARK: - Selection

    @Test func currentActionReturnsSelectedAction() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())
        panel.moveDown()

        let action = panel.currentAction()
        #expect(action?.name == "Show in Finder")
    }

    @Test func currentActionReturnsNilWhenInactive() {
        let panel = ChooserActionPanel()
        #expect(panel.currentAction() == nil)
    }

    @Test func selectByDigitReturnsCorrectAction() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())

        #expect(panel.selectByDigit(1)?.name == "Open")
        #expect(panel.selectByDigit(2)?.name == "Show in Finder")
        #expect(panel.selectByDigit(3)?.name == "Copy Path")
    }

    @Test func selectByDigitReturnsNilForOutOfRange() {
        let panel = ChooserActionPanel()
        panel.activate(for: makeDummyChoice(), actions: makeDummyActions())

        #expect(panel.selectByDigit(0) == nil)
        #expect(panel.selectByDigit(4) == nil)
        #expect(panel.selectByDigit(10) == nil)
    }
}
