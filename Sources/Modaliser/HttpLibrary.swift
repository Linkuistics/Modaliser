import Foundation
import LispKit

/// Native LispKit library providing HTTP GET requests.
/// Scheme name: (modaliser http)
///
/// Provides: http-get
final class HttpLibrary: NativeLibrary {

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "http"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("http-get", httpGetFunction))
    }

    /// (http-get url callback) -> void
    /// Performs an async HTTP GET request.
    /// On success: calls (callback response-string)
    /// On error:   calls (callback #f)
    private func httpGetFunction(_ urlExpr: Expr, _ callbackExpr: Expr) throws -> Expr {
        let urlString = try urlExpr.asString()
        guard case .procedure = callbackExpr else {
            throw RuntimeError.custom("eval", "http-get: second argument must be a procedure", [])
        }
        guard let url = URL(string: urlString) else {
            throw RuntimeError.custom("eval", "http-get: invalid URL: \(urlString)", [])
        }
        guard self.context.evaluator != nil else {
            throw RuntimeError.custom("eval", "http-get: evaluator not available", [])
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
                guard let evaluator = context.evaluator else { return }
                _ = evaluator.execute { machine in
                    try machine.apply(callbackExpr, to: .pair(result, .null))
                }
            }
        }.resume()

        return .void
    }
}
