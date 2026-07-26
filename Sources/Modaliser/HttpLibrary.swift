import Foundation
import LispKit

/// Native LispKit library providing the raw capability to fetch a URL.
/// Scheme name: (modaliser http-native)
///
/// Provides: http-get-native
///
/// **This is not the library the tree imports.** Reaching the network is an
/// outward native capability in exactly the sense ADR-0023 governs: it leaves
/// the machine, and it answers differently — or not at all — depending on a
/// third party nobody in this repository controls. So it is held behind the
/// portable seam `(modaliser http)`, which ships with no runner installed and
/// is wired to this procedure by `root.scm` at bootstrap. The `-native` suffix
/// is the tell: an import of this library from anywhere but the host bootstrap
/// is a bypass of that seam, and `scripts/check-portable-surface.sh` fails the
/// build on one.
final class HttpLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "http-native"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("http-get-native", httpGetFunction))
    }

    /// (http-get-native url callback) -> void
    /// Performs an async request through the URL loading system.
    /// On success: calls (callback response-string)
    /// On error:   calls (callback #f)
    private func httpGetFunction(_ urlExpr: Expr, _ callbackExpr: Expr) throws -> Expr {
        let urlString = try urlExpr.asString()
        guard case .procedure = callbackExpr else {
            throw RuntimeError.custom(
                "eval", "http-get-native: second argument must be a procedure", [])
        }
        guard let url = URL(string: urlString) else {
            throw RuntimeError.custom("eval", "http-get-native: invalid URL: \(urlString)", [])
        }
        guard self.context.evaluator != nil else {
            throw RuntimeError.custom("eval", "http-get-native: evaluator not available", [])
        }

        let context = self.context
        URLSession.shared.dataTask(with: url) { data, response, error in
            let result: Expr
            if let data = data, error == nil,
               let body = String(data: data, encoding: .utf8) {
                result = .makeString(body)
            } else {
                result = .false
            }
            DispatchQueue.main.async {
                context.withEvalLockNonBlocking {
                    guard let evaluator = context.evaluator else { return }
                    _ = evaluator.execute { machine in
                        try machine.apply(callbackExpr, to: .pair(result, .null))
                    }
                }
            }
        }.resume()

        return .void
    }
}
