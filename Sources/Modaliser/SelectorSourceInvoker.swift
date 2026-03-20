import Foundation
import LispKit

/// Calls a selector's Scheme source function and marshals the result into ChooserChoice objects.
/// Each choice retains its original Scheme alist for round-tripping back to callbacks.
struct SelectorSourceInvoker {
    let engine: SchemeEngine

    /// Invoke the source lambda and convert the result list to Swift choices.
    func invoke(source: Expr) throws -> [ChooserChoice] {
        guard case .procedure = source else {
            throw SelectorSourceError.notAProcedure(source)
        }
        let result = engine.context.evaluator.execute { machine in
            try machine.apply(source, to: .null)
        }
        if case .error(let err) = result {
            throw err
        }
        return marshalChoices(from: result)
    }

    // MARK: - Private

    private func marshalChoices(from expr: Expr) -> [ChooserChoice] {
        var choices: [ChooserChoice] = []
        var current = expr
        while case .pair(let head, let tail) = current {
            choices.append(marshalOneChoice(from: head))
            current = tail
        }
        return choices
    }

    private func marshalOneChoice(from alist: Expr) -> ChooserChoice {
        ChooserChoice(
            text: SchemeAlistLookup.lookupString(alist, key: "text") ?? "",
            subText: SchemeAlistLookup.lookupString(alist, key: "subText"),
            icon: SchemeAlistLookup.lookupString(alist, key: "icon"),
            iconType: SchemeAlistLookup.lookupString(alist, key: "iconType"),
            schemeValue: alist
        )
    }
}

enum SelectorSourceError: Error, LocalizedError {
    case notAProcedure(Expr)

    var errorDescription: String? {
        switch self {
        case .notAProcedure(let expr):
            return "Selector source must be a Scheme procedure, got: \(expr)"
        }
    }
}
