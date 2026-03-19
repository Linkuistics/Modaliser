import LispKit

/// The result of dispatching a key press through the modal state machine.
enum KeyDispatchResult: Equatable {
    /// Navigated into a group (modal stays active).
    case navigated
    /// Executed a command's Scheme lambda. Contains the action Expr.
    case executed(Expr)
    /// Opened a selector (chooser takes over from modal).
    case openSelector(SelectorDefinition)
    /// No binding found for the pressed key.
    case noBinding(String)

    static func == (lhs: KeyDispatchResult, rhs: KeyDispatchResult) -> Bool {
        switch (lhs, rhs) {
        case (.navigated, .navigated):
            return true
        case (.executed(let a), .executed(let b)):
            return a == b
        case (.openSelector(let a), .openSelector(let b)):
            return a.key == b.key && a.label == b.label
        case (.noBinding(let a), .noBinding(let b)):
            return a == b
        default:
            return false
        }
    }
}
